import XCTest
@testable import AlphaSyncHardware

final class ModeSwitchTests: XCTestCase {
    func testUSBExclusiveAccessErrorSuggestsClosingKeyboardSetupAssistant() {
        let domain = "IOUSBHostErrorDomain"
        let code = -536870203
        let error = NSError(domain: domain, code: code, userInfo: [NSLocalizedDescriptionKey: "Failed to create IOUSBHostObject."])
        let message = USBDiscovery.modeSwitchFailureMessage(error)
        XCTAssertTrue(message.contains("Close Keyboard Setup Assistant"))
        XCTAssertTrue(message.contains("Try Again"))
        XCTAssertTrue(message.contains("Failed to create IOUSBHostObject."))
        XCTAssertTrue(message.contains("(IOUSBHostErrorDomain, -536870203)"))

        for other in [NSError(domain: "OtherDomain", code: code), NSError(domain: domain, code: -1)] {
            let generalMessage = USBDiscovery.modeSwitchFailureMessage(other)
            XCTAssertFalse(generalMessage.contains("Keyboard Setup Assistant"))
            XCTAssertTrue(generalMessage.contains("could not switch from keyboard mode"))
        }
    }

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
