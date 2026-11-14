import Foundation
import XCTest
import AlphaSyncCore
@testable import AlphaSyncHardware

private enum PipeFailure: Error, Equatable { case transfer, recovery, abort }

private final class TestUSBPipe: USBPipeIO {
    var packets: [Data] = []
    var timeouts: [TimeInterval] = []
    var recoveries = 0, aborts = 0
    var perform: ((NSMutableData, Int) throws -> Int)?
    var recoveryFails = false, abortFails = false

    func transfer(_ buffer: NSMutableData, timeout: TimeInterval) throws -> Int {
        packets.append(Data(bytes: buffer.bytes, count: buffer.length))
        timeouts.append(timeout)
        return try perform?(buffer, packets.count) ?? buffer.length
    }
    func clearStall() throws {
        recoveries += 1
        if recoveryFails { throw PipeFailure.recovery }
    }
    func abort() throws {
        aborts += 1
        if abortFails { throw PipeFailure.abort }
    }
}

final class USBHostTransportTests: XCTestCase {
    func testReadReturnsOnlyActualBytesIncludingShortAndEmptyPackets() throws {
        let input = TestUSBPipe(), output = TestUSBPipe()
        input.perform = { buffer, call in
            buffer.mutableBytes.assumingMemoryBound(to: UInt8.self)[0] = 0x23
            return call == 1 ? 1 : 0
        }
        let transport = USBHostTransport(input: input, output: output, releaseInterface: {})
        XCTAssertEqual(try transport.read(maximum: 8, timeout: 1), Data([0x23]))
        XCTAssertEqual(try transport.read(maximum: 8, timeout: 1), Data())
        XCTAssertEqual(input.packets.map(\.count), [8, 8])
        XCTAssertEqual(input.recoveries, 0)
        XCTAssertTrue(output.packets.isEmpty)
    }

    func testWritesUseEightBytePacketsAndAnUnpaddedTailFromSlicedData() throws {
        let input = TestUSBPipe(), output = TestUSBPipe()
        let transport = USBHostTransport(input: input, output: output, releaseInterface: {})
        let source = Data((0..<30).map(UInt8.init))
        let slice = source[3..<26]
        try transport.write(slice, timeout: 1)
        XCTAssertEqual(output.packets.map(\.count), [8, 8, 7])
        XCTAssertEqual(output.packets.reduce(Data(), +), Data(slice))
        XCTAssertTrue(output.timeouts.allSatisfy { $0 > 0 && $0 <= 1 })
        XCTAssertTrue(zip(output.timeouts, output.timeouts.dropFirst()).allSatisfy { pair in pair.0 >= pair.1 })
        XCTAssertTrue(input.packets.isEmpty)
    }

    func testEmptyWriteDoesNotSubmitAZeroLengthPacket() throws {
        let input = TestUSBPipe(), output = TestUSBPipe()
        let transport = USBHostTransport(input: input, output: output, releaseInterface: {})
        try transport.write(Data(), timeout: 1)
        XCTAssertTrue(output.packets.isEmpty)
    }

    func testPartialWriteFailsWithoutRetryingOrSendingLaterPackets() {
        let input = TestUSBPipe(), output = TestUSBPipe()
        output.perform = { _, _ in 7 }
        let transport = USBHostTransport(input: input, output: output, releaseInterface: {})
        XCTAssertThrowsError(try transport.write(Data(repeating: 1, count: 23), timeout: 1))
        XCTAssertEqual(output.packets.count, 1)
        XCTAssertEqual(output.recoveries, 1)
        XCTAssertEqual(input.recoveries, 0)
    }

    func testFailureAfterOneWrittenPacketDoesNotReplayAnyBytes() {
        let input = TestUSBPipe(), output = TestUSBPipe()
        output.perform = { buffer, call in
            if call == 2 { throw PipeFailure.transfer }
            return buffer.length
        }
        let transport = USBHostTransport(input: input, output: output, releaseInterface: {})
        XCTAssertThrowsError(try transport.write(Data((0..<23).map(UInt8.init)), timeout: 1)) {
            XCTAssertEqual($0 as? PipeFailure, .transfer)
        }
        XCTAssertEqual(output.packets, [Data((0..<8).map(UInt8.init)), Data((8..<16).map(UInt8.init))])
        XCTAssertEqual(output.recoveries, 1)
        XCTAssertEqual(input.recoveries, 0)
    }

    func testReadFailurePreservesTheOriginalErrorIfStallRecoveryFails() {
        let input = TestUSBPipe(), output = TestUSBPipe()
        input.perform = { _, _ in throw PipeFailure.transfer }
        input.recoveryFails = true
        let transport = USBHostTransport(input: input, output: output, releaseInterface: {})
        XCTAssertThrowsError(try transport.read(maximum: 8, timeout: 1)) {
            XCTAssertEqual($0 as? PipeFailure, .transfer)
        }
        XCTAssertEqual(input.packets.count, 1)
        XCTAssertEqual(input.recoveries, 1)
        XCTAssertEqual(output.recoveries, 0)
    }

    func testInvalidReadCountsCannotCopyBeyondTheOwnedBuffer() {
        for count in [-1, 9] {
            let input = TestUSBPipe(), output = TestUSBPipe()
            input.perform = { _, _ in count }
            let transport = USBHostTransport(input: input, output: output, releaseInterface: {})
            XCTAssertThrowsError(try transport.read(maximum: 8, timeout: 1))
            XCTAssertEqual(input.recoveries, 1)
        }
    }

    func testInvalidBoundsAndTimeoutsNeverReachOrResetAPipe() {
        let input = TestUSBPipe(), output = TestUSBPipe()
        let transport = USBHostTransport(input: input, output: output, releaseInterface: {})
        for maximum in [-1, 0, 9, Int.max] {
            XCTAssertThrowsError(try transport.read(maximum: maximum, timeout: 1))
        }
        for timeout in [0, -1, TimeInterval.infinity, TimeInterval.nan] {
            XCTAssertThrowsError(try transport.read(maximum: 8, timeout: timeout))
            XCTAssertThrowsError(try transport.write(Data([1]), timeout: timeout))
            XCTAssertThrowsError(try transport.write(Data(), timeout: timeout))
        }
        XCTAssertTrue(input.packets.isEmpty)
        XCTAssertTrue(output.packets.isEmpty)
        XCTAssertEqual(input.recoveries + output.recoveries, 0)
    }

    func testCloseAbortsBothPipesBeforeReleasingTheInterfaceExactlyOnce() {
        let input = TestUSBPipe(), output = TestUSBPipe()
        var releases = 0
        let transport = USBHostTransport(input: input, output: output, releaseInterface: {
            XCTAssertEqual(input.aborts, 1)
            XCTAssertEqual(output.aborts, 1)
            releases += 1
        })
        transport.close(); transport.close()
        XCTAssertEqual(releases, 1)
        XCTAssertEqual(input.aborts, 1)
        XCTAssertEqual(output.aborts, 1)
    }

    func testAbortErrorsDoNotPreventRemainingCleanup() {
        let input = TestUSBPipe(), output = TestUSBPipe()
        input.abortFails = true; output.abortFails = true
        var releases = 0
        let transport = USBHostTransport(input: input, output: output, releaseInterface: { releases += 1 })
        transport.close()
        XCTAssertEqual(input.aborts, 1)
        XCTAssertEqual(output.aborts, 1)
        XCTAssertEqual(releases, 1)
    }

    func testClosedTransportRejectsAllIOIncludingEmptyWrites() {
        let input = TestUSBPipe(), output = TestUSBPipe()
        let transport = USBHostTransport(input: input, output: output, releaseInterface: {})
        transport.close()
        XCTAssertThrowsError(try transport.read(maximum: 8, timeout: 1))
        XCTAssertThrowsError(try transport.write(Data([1]), timeout: 1))
        XCTAssertThrowsError(try transport.write(Data(), timeout: 1))
        XCTAssertTrue(input.packets.isEmpty)
        XCTAssertTrue(output.packets.isEmpty)
    }

    func testDeinitialisationPerformsTheSameCompleteCleanup() {
        let input = TestUSBPipe(), output = TestUSBPipe()
        var releases = 0
        var transport: USBHostTransport? = USBHostTransport(input: input, output: output, releaseInterface: { releases += 1 })
        weak var reference = transport
        XCTAssertNotNil(reference)
        transport = nil
        XCTAssertNil(reference)
        XCTAssertEqual(input.aborts, 1)
        XCTAssertEqual(output.aborts, 1)
        XCTAssertEqual(releases, 1)
    }
}
