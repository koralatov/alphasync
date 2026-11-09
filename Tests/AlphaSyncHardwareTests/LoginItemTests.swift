import Foundation
import ServiceManagement
import XCTest
@testable import AlphaSyncUI

@MainActor
private final class FakeLoginItem: LoginItemManaging {
    var status: SMAppService.Status = .notRegistered
    var registration: (() throws -> Void)?
    var removal: (() throws -> Void)?
    var registrations = 0
    func register() throws { registrations += 1; try registration?(); if status != .requiresApproval { status = .enabled } }
    func unregister() throws { try removal?(); status = .notRegistered }
}

@MainActor
final class LoginItemTests: XCTestCase {
    private func defaults() -> UserDefaults {
        let name = "AlphaSync-LoginTests-" + UUID().uuidString
        addTeardownBlock { UserDefaults(suiteName: name)?.removePersistentDomain(forName: name) }
        return UserDefaults(suiteName: name)!
    }

    func testIntentIsSavedBeforeTheHelperCanStart() {
        let defaults = defaults(), item = FakeLoginItem()
        let preferences = Preferences(defaults: defaults, loginItem: item)
        item.registration = { XCTAssertTrue(defaults.bool(forKey: "AutoRun")) }
        preferences.setAutomaticOpening(true)
        XCTAssertTrue(preferences.automaticOpening)
        XCTAssertEqual(item.status, .enabled)
    }

    func testRegistrationFailureRestoresThePreviousIntent() {
        let defaults = defaults(), item = FakeLoginItem()
        item.registration = { throw CocoaError(.fileReadNoPermission) }
        let preferences = Preferences(defaults: defaults, loginItem: item)
        preferences.setAutomaticOpening(true)
        XCTAssertFalse(preferences.automaticOpening)
        XCTAssertFalse(defaults.bool(forKey: "AutoRun"))
        XCTAssertTrue(preferences.loginStatus.contains("could not be changed"))
    }

    func testPendingApprovalKeepsTheRequestedIntent() {
        let defaults = defaults(), item = FakeLoginItem()
        item.registration = { item.status = .requiresApproval; throw CocoaError(.fileReadNoPermission) }
        let preferences = Preferences(defaults: defaults, loginItem: item)
        preferences.setAutomaticOpening(true)
        XCTAssertTrue(preferences.automaticOpening)
        XCTAssertTrue(defaults.bool(forKey: "AutoRun"))
        XCTAssertTrue(preferences.loginStatus.contains("Approve AlphaSync"))
    }

    func testAlreadyEnabledRegistrationIsNotRepeated() {
        let item = FakeLoginItem()
        item.status = .enabled
        let preferences = Preferences(defaults: defaults(), loginItem: item)
        preferences.setAutomaticOpening(true)
        XCTAssertEqual(item.registrations, 0)
    }

    func testFailedRemovalRestoresEnabledIntent() {
        let defaults = defaults(), item = FakeLoginItem()
        defaults.set(true, forKey: "AutoRun")
        item.status = .enabled
        item.removal = { throw CocoaError(.fileReadNoPermission) }
        let preferences = Preferences(defaults: defaults, loginItem: item)
        preferences.setAutomaticOpening(false)
        XCTAssertTrue(preferences.automaticOpening)
        XCTAssertTrue(defaults.bool(forKey: "AutoRun"))
    }
}
