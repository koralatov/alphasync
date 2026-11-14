import Foundation
import XCTest
@testable import AlphaSyncCore

/// Literal request layouts follow v1.5.1 ASDevice.cc and ASMessage.h, independently of NeoMessage.
private final class LegacySnapshotWire: NeoTransport {
    static let filelessApplet: UInt16 = 0xb000
    var rejectedUsage: [UInt16: UInt8] = [0: 0x90, LegacySnapshotWire.filelessApplet: 0x90]
    var readOnlyHasFile = false
    var missingAlphaWordFile: UInt8?
    var corruptParameterReply = false
    var requests: [[UInt8]] = []
    let fileData = Data((0..<512).map { UInt8(truncatingIfNeeded: $0) })
    private var incoming = Data()
    private var pendingFile: Data?

    private func packet(_ fields: [UInt8]) -> Data {
        precondition(fields.count == 7)
        return Data(fields + [fields.reduce(UInt8(0), &+)])
    }

    private func sendReply(_ code: UInt8, value: UInt32 = 0, tail: UInt16 = 0) {
        incoming.append(packet([code, UInt8(truncatingIfNeeded: value >> 24),
            UInt8(truncatingIfNeeded: value >> 16), UInt8(truncatingIfNeeded: value >> 8),
            UInt8(truncatingIfNeeded: value), UInt8(tail >> 8), UInt8(truncatingIfNeeded: tail)]))
    }

    private func sendPayload(_ code: UInt8, _ data: Data) {
        let checksum = data.reduce(UInt16(0)) { $0 &+ UInt16($1) }
        sendReply(code, value: UInt32(data.count), tail: checksum)
        incoming.append(data)
    }

    private func header(_ id: UInt16, name: String, files: UInt8) -> Data {
        var bytes = [UInt8](repeating: 0, count: 132)
        bytes.replaceSubrange(0..<4, with: [0xc0, 0xff, 0xee, 0xad])
        bytes[20] = UInt8(id >> 8); bytes[21] = UInt8(truncatingIfNeeded: id)
        bytes[23] = files
        bytes.replaceSubrange(24..<(24 + name.utf8.count), with: name.utf8)
        bytes[60] = 3; bytes[61] = 6
        return Data(bytes)
    }

    private func attributes(_ index: UInt8) -> Data {
        var bytes = [UInt8](repeating: 0, count: 40)
        let name = Array("File \(index)".utf8)
        bytes.replaceSubrange(0..<name.count, with: name)
        bytes[26] = 2; bytes[30] = 2 // Minimum and allocation are both 512 bytes.
        return Data(bytes)
    }

    func read(maximum: Int, timeout: TimeInterval) throws -> Data {
        guard !incoming.isEmpty else { throw NeoError.device("The wire fixture has no pending reply.") }
        let result = Data(incoming.prefix(maximum))
        incoming.removeFirst(result.count)
        return result
    }

    func write(_ data: Data, timeout: TimeInterval) throws {
        if data == Data([1]) { incoming.append(contentsOf: [2, 0x30]); return }
        if data == Data([0x3f, 0xff, 0, 0x72, 0x65, 0x73, 0x65, 0x74]) {
            incoming.removeAll(); pendingFile = nil; return
        }
        if data == Data([0x3f, 0x53, 0x77, 0x74, 0x63, 0x68, 0, 0]) {
            incoming.append(contentsOf: [0x53, 0x77, 0x69, 0x74, 0x63, 0x68, 0x65, 0x64])
            return
        }
        let bytes = Array(data)
        guard bytes.count == 8, bytes.prefix(7).reduce(UInt8(0), &+) == bytes[7] else {
            throw NeoError.invalidData("An outgoing fixture packet is invalid.")
        }
        requests.append(bytes)
        let applet = UInt16(bytes[5]) << 8 | UInt16(bytes[6])
        switch bytes[0] {
        case 0x04:
            guard data == packet([4, 0, 0, 0, 0, 0, 7]) else { break }
            let headers = header(0, name: "System", files: 0) +
                header(0xa000, name: "AlphaWord", files: 8) +
                header(Self.filelessApplet, name: "Fileless Applet", files: 0) +
                header(0xa005, name: "User Dictionary", files: 1)
            sendPayload(0x44, headers)
            return
        case 0:
            guard data == packet([0, 0, 0, 0, 0, 0, 0]) else { break }
            sendPayload(0x40, Data([0, 0, 0, 0, 3, 6, 78, 101, 111, 0, 68, 97, 116, 101, 0]))
            return
        case 0x1a:
            guard data == packet([0x1a, 0, 0, 0, 0, 0, 0]) else { break }
            sendReply(0x58, tail: 256)
            return
        case 0x1b:
            guard data == packet([0x1b, 0, 0, 0, 1, bytes[5], bytes[6]]) else { break }
            if let code = rejectedUsage[applet] {
                if corruptParameterReply && applet == Self.filelessApplet && code == 0x90 {
                    incoming.append(contentsOf: [0x90, 0, 0, 0, 0, 0, 0, 0])
                } else {
                    sendReply(code)
                }
                return
            }
            guard applet == 0xa000 || applet == 0xa005 else { break }
            let count: UInt16 = applet == 0xa000 ? 8 : 1
            sendReply(0x59, value: UInt32(count) * 512, tail: count)
            return
        case 0x13:
            let index = bytes[4]
            guard data == packet([0x13, 0, 0, 0, index, bytes[5], bytes[6]]), index > 0 else { break }
            let exists = (applet == 0xa000 && index <= 8 && index != missingAlphaWordFile) ||
                (applet == 0xa005 && index == 1) ||
                (applet == Self.filelessApplet && readOnlyHasFile && index == 1)
            if exists { sendPayload(0x5a, attributes(index)) }
            else { sendReply(0x90) }
            return
        case 0x0c:
            guard data == packet([0x0c, 0, 0, 0, 0x0b, 0xa0, 0]) else { break }
            sendPayload(0x4b, Data([1, 2, 0x10, 0x10, 0, 4, 0, 0, 0xc8, 0,
                1, 2, 0x10, 0x11, 0, 4, 0, 0, 2, 0]))
            return
        case 0x1c:
            guard data == packet([0x1c, 0, 2, 0, 1, 0xa0, 0]) else { break }
            pendingFile = fileData
            sendReply(0x53, value: 512)
            return
        case 0x10:
            guard data == packet([0x10, 0, 0, 0, 0, 0, 0]), let block = pendingFile else { break }
            sendPayload(0x4d, block)
            pendingFile = nil
            return
        default:
            break
        }
        throw NeoError.invalidData("Unexpected legacy-wire request: \(bytes).")
    }

    func close() {}

    func queried(_ command: UInt8, applet: UInt16) -> Bool {
        requests.contains { $0[0] == command && (UInt16($0[5]) << 8 | UInt16($0[6])) == applet }
    }

    var fileWrites: Int { requests.filter { [0x02, 0x1d, 0x1e, 0x1f].contains($0[0]) }.count }
}

final class SnapshotWireTests: XCTestCase {
    private func snapshot(_ wire: LegacySnapshotWire) throws -> NeoSnapshot {
        try NeoProtocol(transport: wire).snapshot(connection: UUID(), registryID: 1)
    }

    func testSystemAppletDoesNotReceiveAFileCountRequest() throws {
        let wire = LegacySnapshotWire()
        let result = try snapshot(wire)
        XCTAssertEqual(result.systemVersion, "3.6")
        XCTAssertEqual(result.availableRAM, 65536)
        XCTAssertEqual(result.applets.first { $0.id == 0 }?.files.count, 0)
        XCTAssertFalse(wire.queried(0x1b, applet: 0))
        XCTAssertFalse(wire.queried(0x13, applet: 0))
        XCTAssertEqual(wire.fileWrites, 0)
    }

    func testReadOnlyAppletWithoutFilesDoesNotHideOtherApplets() throws {
        let wire = LegacySnapshotWire()
        let result = try snapshot(wire)
        XCTAssertEqual(result.applets.first { $0.id == 0xa000 }?.files.count, 8)
        XCTAssertEqual(result.applets.first { $0.id == 0xa005 }?.files.count, 1)
        XCTAssertEqual(result.applets.first { $0.id == LegacySnapshotWire.filelessApplet }?.files.count, 0)
        XCTAssertTrue(wire.queried(0x1b, applet: LegacySnapshotWire.filelessApplet))
        XCTAssertTrue(wire.queried(0x13, applet: LegacySnapshotWire.filelessApplet))
        XCTAssertEqual(wire.fileWrites, 0)
    }

    func testFileCanBeReadAfterTheWholeSnapshotLoads() throws {
        let wire = LegacySnapshotWire()
        let engine = NeoProtocol(transport: wire)
        _ = try engine.snapshot(connection: UUID(), registryID: 1)
        XCTAssertEqual(try engine.readFile(applet: 0xa000, index: 1), wire.fileData)
        XCTAssertEqual(wire.fileWrites, 0)
    }

    func testWritableAppletParameterFailureStillFailsTheSnapshot() {
        let wire = LegacySnapshotWire()
        wire.rejectedUsage[0xa000] = 0x90
        XCTAssertThrowsError(try snapshot(wire)) { error in
            let failure = error as? NeoReplyError
            XCTAssertEqual(failure?.request, 0x1b)
            XCTAssertEqual(failure?.reply, 0x90)
            XCTAssertEqual(failure?.applet, 0xa000)
            XCTAssertTrue(error.localizedDescription.contains("0x1B"))
            XCTAssertTrue(error.localizedDescription.contains("0xA000"))
            XCTAssertTrue(error.localizedDescription.contains("0x90"))
        }
        XCTAssertFalse(wire.queried(0x13, applet: 0xa000))
        XCTAssertEqual(wire.fileWrites, 0)
    }

    func testOtherRepliesFromAReadOnlyAppletRemainErrors() {
        let wire = LegacySnapshotWire()
        wire.rejectedUsage[LegacySnapshotWire.filelessApplet] = 0x8f
        XCTAssertThrowsError(try snapshot(wire)) { error in
            XCTAssertEqual((error as? NeoReplyError)?.reply, 0x8f)
        }
        XCTAssertFalse(wire.queried(0x13, applet: LegacySnapshotWire.filelessApplet))
        XCTAssertEqual(wire.fileWrites, 0)
    }

    func testFileBearingReadOnlyAppletIsNotTreatedAsEmpty() {
        let wire = LegacySnapshotWire()
        wire.readOnlyHasFile = true
        XCTAssertThrowsError(try snapshot(wire)) { error in
            XCTAssertEqual((error as? NeoReplyError)?.request, 0x1b)
            XCTAssertEqual((error as? NeoReplyError)?.applet, LegacySnapshotWire.filelessApplet)
        }
        XCTAssertTrue(wire.queried(0x13, applet: LegacySnapshotWire.filelessApplet))
        XCTAssertEqual(wire.fileWrites, 0)
    }

    func testMissingAdvertisedFileDoesNotProduceAPartialSnapshot() {
        let wire = LegacySnapshotWire()
        wire.missingAlphaWordFile = 4
        XCTAssertThrowsError(try snapshot(wire)) { error in
            XCTAssertEqual((error as? NeoReplyError)?.request, 0x13)
            XCTAssertEqual((error as? NeoReplyError)?.applet, 0xa000)
        }
        XCTAssertEqual(wire.fileWrites, 0)
    }

    func testCorruptErrorFrameIsNotAcceptedAsAFilelessApplet() {
        let wire = LegacySnapshotWire()
        wire.corruptParameterReply = true
        XCTAssertThrowsError(try snapshot(wire)) { error in
            guard let failure = error as? NeoError, case .invalidData(let reason) = failure else {
                return XCTFail("Expected a checksum failure.")
            }
            XCTAssertTrue(reason.contains("checksum"))
        }
        XCTAssertFalse(wire.queried(0x13, applet: LegacySnapshotWire.filelessApplet))
        XCTAssertEqual(wire.fileWrites, 0)
    }
}
