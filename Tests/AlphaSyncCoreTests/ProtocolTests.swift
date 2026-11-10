import Foundation
import XCTest
@testable import AlphaSyncCore

private final class SimulatedNeo: NeoTransport {
    var incoming = Data()
    var payload = Data(repeating: 0xa7, count: 512)
    var commands: [UInt8] = []
    var writes = 0
    var helloFailures = 0, helloAttempts = 0, resets = 0
    var corruptVerification = false
    var oversizedBlock = false
    var readBlocks = 0
    var maximum: UInt32 = 51200
    private var blockRemaining = 0
    private var pending = Data()
    private var writingAttributes = false
    private var readOffset = 0, readLimit = 0

    private func reply(_ code: UInt8, length: UInt32 = 0, checksum: UInt32 = 0) throws {
        var frame = NeoMessage(command: code)
        try frame.set(length, at: 1, width: 4)
        try frame.set(checksum, at: 5, width: 2)
        incoming.append(frame.data)
    }
    private func replyData(_ code: UInt8, _ data: Data) throws {
        try reply(code, length: UInt32(data.count), checksum: data.reduce(UInt32(0)) { ($0 + UInt32($1)) & 0xffff })
        incoming.append(data)
    }
    func read(maximum: Int, timeout: TimeInterval) throws -> Data {
        guard !incoming.isEmpty else { throw NeoError.device("Simulated missing reply") }
        let result = Data(incoming.prefix(maximum)); incoming.removeFirst(result.count)
        return result
    }
    func write(_ data: Data, timeout: TimeInterval) throws {
        if blockRemaining > 0 {
            guard data.count <= blockRemaining else { throw NeoError.invalidData("Simulated block overrun") }
            pending.append(data); blockRemaining -= data.count
            if blockRemaining == 0 { try reply(0x43) }
            return
        }
        if data == Data([1]) {
            helloAttempts += 1
            if helloFailures > 0 { helloFailures -= 1; incoming.append(0); return }
            incoming.append(contentsOf: [2, 0x30]); return
        }
        if data.count == 8, data.first == 0x3f {
            if data[data.startIndex + 1] == 0x53 { incoming.append(Data("Switched".utf8)) }
            else { resets += 1 }
            return
        }
        let frame = try NeoMessage(data: data)
        commands.append(frame.command)
        switch frame.command {
        case 0x0c:
            var settings = Data([1, 2, 0x10, 0x10, 0, 4])
            settings.appendBigEndian(maximum, width: 4)
            try replyData(0x4b, settings)
        case 0x1a:
            var response = NeoMessage(command: 0x58)
            try response.set(1200, at: 5, width: 2)
            incoming.append(response.data)
        case 0x13:
            let attributes = try NeoFileAttributes(name: "Existing", allocation: payload.count)
            try replyData(0x5a, attributes.raw)
        case 0x1b:
            var response = NeoMessage(command: 0x59)
            try response.set(1, at: 5, width: 2)
            incoming.append(response.data)
        case 0x1c:
            readOffset = 0; readLimit = min(payload.count, Int(try frame.argument(at: 1, width: 3)))
            try reply(0x53)
        case 0x10:
            if oversizedBlock { try reply(0x4d, length: 2048); return }
            let size = min(1024, readLimit - readOffset)
            if size == 0 { try reply(0x4e); return }
            var block = Data(payload[readOffset..<(readOffset + size)])
            if corruptVerification && writes > 0 && readOffset == 0 { block[0] ^= 1 }
            readOffset += size
            readBlocks += 1
            try replyData(0x4d, block)
        case 0x1f:
            writes += 1; pending = Data(); writingAttributes = false
            try reply(0x50)
        case 0x02:
            blockRemaining = Int(try frame.argument(at: 1, width: 4))
            try reply(0x42)
        case 0x15:
            if !writingAttributes { payload = pending }
            try reply(0x51)
        default: throw NeoError.invalidData("Unexpected simulated command \(frame.command)")
        }
    }
    func close() {}
}

final class ProtocolTests: XCTestCase {
    func testTransientHandshakeFailureCanRecoverWithoutWritingFiles() throws {
        let device = SimulatedNeo(); device.helloFailures = 1
        XCTAssertEqual(try NeoProtocol(transport: device).readFile(applet: 0xa000, index: 1), device.payload)
        XCTAssertGreaterThanOrEqual(device.resets, 1)
        XCTAssertEqual(device.writes, 0)
    }
    func testHandshakeRetriesAreBoundedAndLeaveAReset() {
        let device = SimulatedNeo(); device.helloFailures = 10
        XCTAssertThrowsError(try NeoProtocol(transport: device).availableMemory())
        XCTAssertEqual(device.helloAttempts, 3)
        XCTAssertGreaterThanOrEqual(device.resets, 3)
        XCTAssertTrue(device.commands.isEmpty)
    }

    func testReadFileMatchesDeviceBytes() throws {
        let device = SimulatedNeo()
        let engine = NeoProtocol(transport: device)
        XCTAssertEqual(try engine.readFile(applet: 0xa000, index: 1), device.payload)
    }
    func testOversizedReplyIsRejectedBeforeReadingPayload() {
        let device = SimulatedNeo(); device.oversizedBlock = true
        XCTAssertThrowsError(try NeoProtocol(transport: device).readFile(applet: 0xa000, index: 1))
        XCTAssertEqual(device.writes, 0)
    }
    func testCancelledReadStopsBetweenBlocksWithoutWritingFiles() {
        let device = SimulatedNeo()
        device.payload = Data(repeating: 65, count: 4096)
        let engine = NeoProtocol(transport: device)
        XCTAssertThrowsError(try engine.readFile(applet: 0xa000, index: 1) {
            if device.readBlocks > 0 { throw CancellationError() }
        }) { error in
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertEqual(device.readBlocks, 1)
        XCTAssertEqual(device.writes, 0)
    }
    func testOversizedCreationSendsNoWritingCommand() {
        let device = SimulatedNeo()
        XCTAssertThrowsError(try NeoProtocol(transport: device).createFile(Data(repeating: 65, count: 2 * 1024 * 1024), name: "New", applet: 0xa000))
        XCTAssertEqual(device.writes, 0)
        XCTAssertFalse(device.commands.contains(0x1d))
        XCTAssertFalse(device.commands.contains(0x1e))
        XCTAssertFalse(device.commands.contains(0x1f))
    }
    func testReplacementIsReadBack() throws {
        let device = SimulatedNeo()
        let old = device.payload, new = Data((0..<2304).map { UInt8(truncatingIfNeeded: $0) })
        try NeoProtocol(transport: device).writeFile(new, applet: 0xa000, index: 1, expectedOriginal: old)
        XCTAssertEqual(device.payload, new)
        XCTAssertEqual(device.writes, 1)
    }
    func testCancellingTheFinalOriginalReadSendsNoWritingCommand() {
        let device = SimulatedNeo()
        device.payload = Data(repeating: 65, count: 4096)
        let original = device.payload
        XCTAssertThrowsError(try NeoProtocol(transport: device).writeFile(Data(repeating: 66, count: 512),
            applet: 0xa000, index: 1, expectedOriginal: original, checkingCancellationBeforeWrite: {
                if device.readBlocks > 0 { throw CancellationError() }
            })) { XCTAssertTrue($0 is CancellationError) }
        XCTAssertEqual(device.payload, original)
        XCTAssertEqual(device.readBlocks, 1)
        XCTAssertEqual(device.writes, 0)
        XCTAssertFalse(device.commands.contains(0x1f))
    }
    func testCancellationAfterWritingBeginsDoesNotInterruptVerification() throws {
        let device = SimulatedNeo(), replacement = Data(repeating: 66, count: 2048)
        let original = device.payload
        try NeoProtocol(transport: device).writeFile(replacement, applet: 0xa000, index: 1, expectedOriginal: original,
            checkingCancellationBeforeWrite: {
                if device.writes > 0 { throw CancellationError() }
            })
        XCTAssertEqual(device.payload, replacement)
        XCTAssertEqual(device.writes, 1)
    }
    func testVerificationFailureDoesNotClaimTheOriginalWasPreserved() {
        let device = SimulatedNeo(); device.corruptVerification = true
        let engine = NeoProtocol(transport: device), original = device.payload
        XCTAssertThrowsError(try engine.writeFile(Data(repeating: 66, count: 512), applet: 0xa000, index: 1, expectedOriginal: original)) { error in
            XCTAssertNotNil(error as? NeoWriteError)
            XCTAssertTrue(error.localizedDescription.contains("may already have changed"))
        }
        XCTAssertEqual(device.writes, 1)
    }
    func testChangedOriginalStopsTheWrite() {
        let device = SimulatedNeo()
        XCTAssertThrowsError(try NeoProtocol(transport: device).writeFile(Data(repeating: 66, count: 512), applet: 0xa000, index: 1, expectedOriginal: Data([1])))
        XCTAssertEqual(device.writes, 0)
    }
}
