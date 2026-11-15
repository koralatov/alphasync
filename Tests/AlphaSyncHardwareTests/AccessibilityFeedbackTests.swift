import Foundation
import XCTest
import AlphaSyncCore
@testable import AlphaSyncUI
@testable import AlphaSyncHardware

@MainActor
final class AccessibilityFeedbackTests: XCTestCase {
    func testRelatedConnectionAndFailureChangesProduceOneCurrentAnnouncement() async throws {
        var messages: [String] = []
        let feedback = AccessibilityAnnouncements { messages.append($0) }
        feedback.connectionChanged(count: 1, issue: nil)
        feedback.connectionChanged(count: 1, issue: "A second Neo could not be opened.")
        feedback.completed("Neo files refreshed.")
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(messages, ["Neo connected.  A second Neo could not be opened."])
        feedback.connectionChanged(count: 1, issue: "A second Neo could not be opened.")
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertEqual(messages.count, 1)
    }

    private func store(_ feedback: AccessibilityAnnouncements) -> AppStore {
        let domain = "AlphaSync-AccessibilityTests-" + UUID().uuidString
        addTeardownBlock { UserDefaults(suiteName: domain)?.removePersistentDomain(forName: domain) }
        let observations = SimulatedObservations()
        let service = DeviceService(discoveryFactory: { SimulatedDiscovery(SimulatedConfiguration(), observations) })
        return AppStore(service: service, preferences: Preferences(defaults: UserDefaults(suiteName: domain)!),
                        monitoringEnabled: false, announcements: feedback)
    }

    func testRefreshAndRenameAnnounceCompletionWithoutRepeatingTheInitialConnection() async throws {
        var messages: [String] = []
        let store = store(AccessibilityAnnouncements { messages.append($0) })
        await store.refresh()
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(messages, ["Neo connected."])
        await store.refresh()
        XCTAssertEqual(messages.last, "Neo files refreshed.")
        let file = try XCTUnwrap(store.files.first)
        await store.rename(file.id, to: "Renamed")
        XCTAssertEqual(messages.last, "File renamed.")
        await store.shutdown()
    }

    func testAReplacementWarningStaysBusyWithoutFalseTransferProgressOrCompletion() async throws {
        var messages: [String] = []
        let store = store(AccessibilityAnnouncements { messages.append($0) })
        await store.refresh()
        try await Task.sleep(for: .milliseconds(300))
        messages.removeAll()
        store.selection = [try XCTUnwrap(store.files.first?.id)]
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("Replacement.txt")
        try Data("Replacement text".utf8).write(to: source)
        store.beginImport()
        let task = try XCTUnwrap(store.finishImport(.success([source])))
        await task.value
        XCTAssertNotNil(store.pendingChange)
        XCTAssertTrue(store.busy)
        XCTAssertFalse(store.isPerformingOperation)
        XCTAssertTrue(messages.isEmpty)
        await store.shutdown()
    }

    func testShutdownCancelsAPendingConnectionAnnouncement() async throws {
        var messages: [String] = []
        let store = store(AccessibilityAnnouncements { messages.append($0) })
        await store.refresh()
        await store.shutdown()
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertTrue(messages.isEmpty)
    }
}
