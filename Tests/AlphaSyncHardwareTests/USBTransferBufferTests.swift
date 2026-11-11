import Foundation
import XCTest
@testable import AlphaSyncHardware

private enum BufferFixtureError: Error, Equatable { case transfer }

final class USBTransferBufferTests: XCTestCase {
    func testModeSwitchPayloadSupportsTheFoundationOperationsUsedByIOUSBHost() throws {
        let payload = Data([0xe0])
        try USBTransferBuffers.write(payload) { buffer in
            XCTAssertEqual(buffer.length, 1)
            // The build 155 crash was an exception from a kernel buffer’s bytes getter.
            XCTAssertEqual(Data(bytes: buffer.bytes, count: buffer.length), payload)
            let originalLength = buffer.length
            buffer.length = originalLength
            XCTAssertEqual(Data(bytes: buffer.bytes, count: buffer.length), payload)
            return 1
        }
    }

    func testOutputBufferOwnsItsBytesWithoutChangingTheSource() throws {
        let payload = Data([1, 2, 3, 4, 5, 6, 7, 8])
        try USBTransferBuffers.write(payload) { buffer in
            XCTAssertEqual(Data(bytes: buffer.bytes, count: buffer.length), payload)
            buffer.mutableBytes.storeBytes(of: UInt8(99), as: UInt8.self)
            return 8
        }
        XCTAssertEqual(payload, Data([1, 2, 3, 4, 5, 6, 7, 8]))
    }

    func testInputCopiesOnlyTheTransferredBytesAndOwnsTheResult() throws {
        var supplied: NSMutableData?
        let result = try USBTransferBuffers.read(maximum: 8) { buffer in
            supplied = buffer
            XCTAssertEqual(buffer.length, 8)
            let bytes = buffer.mutableBytes.assumingMemoryBound(to: UInt8.self)
            for index in 0..<8 { bytes[index] = UInt8(index + 1) }
            return 3
        }
        XCTAssertEqual(result, Data([1, 2, 3]))
        supplied?.mutableBytes.storeBytes(of: UInt8(99), as: UInt8.self)
        XCTAssertEqual(result, Data([1, 2, 3]))
    }

    func testZeroByteInputReturnsAnEmptyResult() throws {
        let result = try USBTransferBuffers.read(maximum: 8) { _ in 0 }
        XCTAssertTrue(result.isEmpty)
    }

    func testInvalidInputCountsStopBeforeCopyingMemory() {
        for count in [-1, 9, Int.max] {
            XCTAssertThrowsError(try USBTransferBuffers.read(maximum: 8) { _ in count })
        }
        XCTAssertThrowsError(try USBTransferBuffers.read(maximum: 8) { buffer in
            buffer.length = 2
            return 3
        })
    }

    func testInvalidBufferSizesNeverCallTheTransfer() {
        var calls = 0
        for size in [-1, 0, Int(UInt16.max) + 1, Int.max] {
            XCTAssertThrowsError(try USBTransferBuffers.read(maximum: size) { _ in calls += 1; return 0 })
        }
        for payload in [Data(), Data(repeating: 0, count: Int(UInt16.max) + 1)] {
            XCTAssertThrowsError(try USBTransferBuffers.write(payload) { _ in calls += 1; return 0 })
        }
        XCTAssertEqual(calls, 0)
    }

    func testIncompleteAndInvalidOutputCountsFail() {
        for count in [-1, 0, 2, Int.max] {
            XCTAssertThrowsError(try USBTransferBuffers.write(Data([0xe0])) { _ in count })
        }
    }

    func testUnderlyingTransferErrorsArePreserved() {
        XCTAssertThrowsError(try USBTransferBuffers.read(maximum: 8) { _ in throw BufferFixtureError.transfer }) { error in
            XCTAssertEqual(error as? BufferFixtureError, .transfer)
        }
        XCTAssertThrowsError(try USBTransferBuffers.write(Data([0xe0])) { _ in throw BufferFixtureError.transfer }) { error in
            XCTAssertEqual(error as? BufferFixtureError, .transfer)
        }
    }
}
