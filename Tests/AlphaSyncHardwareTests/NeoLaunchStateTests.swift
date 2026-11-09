import XCTest
@testable import AlphaSyncHardware

final class NeoLaunchStateTests: XCTestCase {
    func testFailureKeepsTheAttachmentPendingUntilASuccessfulRetry() throws {
        var state = NeoLaunchState()
        let now = ContinuousClock.now
        state.observe([1])
        let first = try XCTUnwrap(state.beginAttempt(appIsRunning: false, now: now))
        state.finish(first, succeeded: false, now: now)
        XCTAssertNil(state.beginAttempt(appIsRunning: false, now: now))
        XCTAssertEqual(state.retryDelay(from: now), .seconds(1))
        let second = try XCTUnwrap(state.beginAttempt(appIsRunning: false, now: now.advanced(by: .seconds(1))))
        state.finish(second, succeeded: true, now: now)
        XCTAssertNil(state.retryDelay(from: now))
        state.observe([1])
        XCTAssertNil(state.beginAttempt(appIsRunning: false, now: now.advanced(by: .seconds(20))))
    }

    func testRetriesStopAfterThreeAttemptsAndReconnectionAllowsAnother() throws {
        var state = NeoLaunchState()
        var now = ContinuousClock.now
        state.observe([1])
        for _ in 0..<3 {
            let attempt = try XCTUnwrap(state.beginAttempt(appIsRunning: false, now: now))
            state.finish(attempt, succeeded: false, now: now)
            now = now.advanced(by: .seconds(5))
        }
        XCTAssertNil(state.beginAttempt(appIsRunning: false, now: now))
        XCTAssertNil(state.retryDelay(from: now))
        state.observe([])
        state.observe([1])
        XCTAssertNotNil(state.beginAttempt(appIsRunning: false, now: now))
    }

    func testDetachmentCancelsThePendingRetry() throws {
        var state = NeoLaunchState()
        let now = ContinuousClock.now
        state.observe([1])
        let attempt = try XCTUnwrap(state.beginAttempt(appIsRunning: false, now: now))
        state.finish(attempt, succeeded: false, now: now)
        state.observe([])
        XCTAssertNil(state.retryDelay(from: now))
        XCTAssertNil(state.beginAttempt(appIsRunning: false, now: now.advanced(by: .seconds(10))))
    }

    func testAnAlreadyRunningAppConsumesTheAttachmentWithoutOpeningAgain() {
        var state = NeoLaunchState()
        let now = ContinuousClock.now
        state.observe([1, 2])
        XCTAssertNil(state.beginAttempt(appIsRunning: true, now: now))
        XCTAssertNil(state.beginAttempt(appIsRunning: false, now: now))
        state.observe([1])
        state.observe([1, 2])
        XCTAssertNotNil(state.beginAttempt(appIsRunning: false, now: now))
    }

    func testAttachmentChangesCannotStartConcurrentLaunches() throws {
        var state = NeoLaunchState()
        let now = ContinuousClock.now
        state.observe([1])
        let attempt = try XCTUnwrap(state.beginAttempt(appIsRunning: false, now: now))
        state.observe([1, 2])
        XCTAssertNil(state.beginAttempt(appIsRunning: false, now: now))
        state.finish(attempt, succeeded: true, now: now)
        XCTAssertNotNil(state.beginAttempt(appIsRunning: false, now: now))
    }
}
