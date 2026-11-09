import XCTest
@testable import AlphaSyncHardware

final class ModeSwitchTests: XCTestCase {
    func testFailedDeviceWaitsForExplicitRetryAndKeepsItsError() {
        var state = ModeSwitchState()
        state.retainAttached([1])
        XCTAssertTrue(state.shouldAttempt(1, retryFailures: false))
        state.recordFailure(1, message: "Access denied")

        state.retainAttached([1])
        XCTAssertEqual(state.issue, "Access denied")
        XCTAssertFalse(state.shouldAttempt(1, retryFailures: false))
        XCTAssertTrue(state.shouldAttempt(1, retryFailures: true))

        state.recordSuccess(1)
        XCTAssertNil(state.issue)
        XCTAssertFalse(state.shouldAttempt(1, retryFailures: true))
    }

    func testDisconnectionAllowsANewAttempt() {
        var state = ModeSwitchState()
        state.recordFailure(1, message: "Access denied")
        state.retainAttached([])
        XCTAssertNil(state.issue)
        state.retainAttached([1])
        XCTAssertTrue(state.shouldAttempt(1, retryFailures: false))
    }

    func testOneFailureDoesNotForgetOtherAttachedDevices() {
        var state = ModeSwitchState()
        state.recordSuccess(1)
        state.recordFailure(2, message: "Second device failed")
        state.retainAttached([1, 2])
        XCTAssertFalse(state.shouldAttempt(1, retryFailures: false))
        XCTAssertEqual(state.issue, "Second device failed")
    }
}
