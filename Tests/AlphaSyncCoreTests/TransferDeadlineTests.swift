import XCTest
@testable import AlphaSyncCore

final class TransferDeadlineTests: XCTestCase {
    func testElapsedTimeExhaustsTheOriginalBudget() throws {
        let start = ContinuousClock.now
        let deadline = try TransferDeadline(timeout: 20, start: start)
        XCTAssertEqual(try deadline.remaining(at: start.advanced(by: .seconds(7.5))), 12.5, accuracy: 0.000_001)
        XCTAssertThrowsError(try deadline.remaining(at: start.advanced(by: .seconds(20))))
        XCTAssertThrowsError(try deadline.remaining(at: start.advanced(by: .seconds(21))))
    }

    func testInvalidTimeoutsAreRejected() {
        for timeout in [0.0, -1.0, .infinity, .nan] {
            XCTAssertThrowsError(try TransferDeadline(timeout: timeout))
        }
    }
}
