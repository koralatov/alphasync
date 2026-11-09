import Foundation
import XCTest
@testable import AlphaSyncHardware

final class RequestCancellationTests: XCTestCase {
    func testCancelledQueuedWorkDoesNotRun() async throws {
        let service = DeviceService()
        let started = expectation(description: "First request started")
        let gate = DispatchSemaphore(value: 0)
        let first = Task {
            try await service.perform { _ in
                started.fulfill()
                gate.wait()
                return 1
            }
        }
        await fulfillment(of: [started], timeout: 3)
        let queued = Task {
            try await service.perform { _ in
                XCTFail("Cancelled queued work reached the device executor")
                return 2
            }
        }
        queued.cancel()
        gate.signal()
        _ = try await first.value
        do {
            _ = try await queued.value
            XCTFail("Cancelled request unexpectedly succeeded")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        await service.shutdown()
    }

    func testCancellationDoesNotInterruptProtectedWorkAlreadyStarted() async throws {
        let service = DeviceService()
        let started = expectation(description: "Protected request started")
        let gate = DispatchSemaphore(value: 0)
        let request = Task {
            try await service.perform { _ in
                started.fulfill()
                gate.wait()
                return 42
            }
        }
        await fulfillment(of: [started], timeout: 3)
        request.cancel()
        gate.signal()
        let result = try await request.value
        XCTAssertEqual(result, 42)
        await service.shutdown()
    }
}
