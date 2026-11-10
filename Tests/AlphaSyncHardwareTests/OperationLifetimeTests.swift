import Foundation
import XCTest
import AlphaSyncCore
@testable import AlphaSyncHardware
@testable import AlphaSyncUI

private final class OperationGate: Sendable {
    let entered = StopRequest()
    let semaphore = DispatchSemaphore(value: 0)
    func wait() { entered.stop(); semaphore.wait() }
    func release() { semaphore.signal() }
}

@MainActor
final class OperationLifetimeTests: XCTestCase {
    private func store(_ configuration: SimulatedConfiguration, _ observations: SimulatedObservations) -> AppStore {
        let domain = "AlphaSync-LifetimeTests-" + UUID().uuidString
        addTeardownBlock { UserDefaults(suiteName: domain)?.removePersistentDomain(forName: domain) }
        return AppStore(service: DeviceService(discoveryFactory: { SimulatedDiscovery(configuration, observations) }),
                        preferences: Preferences(defaults: UserDefaults(suiteName: domain)!), monitoringEnabled: false)
    }

    private func eventually(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !condition() && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(condition(), file: file, line: line)
    }

    func testQuitStopsClearPreparationWithoutWritingOrPresentingAConfirmation() async throws {
        let gate = OperationGate(), observations = SimulatedObservations()
        defer { gate.release() }
        let store = store(SimulatedConfiguration(beforeRead: { if $0 == 2 { gate.wait() } }), observations)
        await store.refresh()
        let preparing = Task { await store.requestClear() }
        try await eventually { gate.entered.isRequested }
        let quitting = Task { await store.shutdown() }
        try await eventually { store.shuttingDown }
        gate.release()
        await preparing.value
        await quitting.value
        XCTAssertEqual(observations.writeCount, 0)
        XCTAssertEqual(observations.closeCount, 1)
        XCTAssertNil(store.pendingChange)
        XCTAssertNil(store.notice)
    }

    func testQuitStopsReplacementPreparationWithoutWriting() async throws {
        let gate = OperationGate(), observations = SimulatedObservations()
        defer { gate.release() }
        let store = store(SimulatedConfiguration(beforeRead: { if $0 == 1 { gate.wait() } }), observations)
        await store.refresh()
        store.selection = [try XCTUnwrap(store.files.first?.id)]
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("Replacement.txt")
        try Data("Replacement text".utf8).write(to: source)
        store.beginImport()
        let preparing = try XCTUnwrap(store.finishImport(.success([source])))
        try await eventually { gate.entered.isRequested }
        let quitting = Task { await store.shutdown() }
        try await eventually { store.shuttingDown }
        gate.release()
        await preparing.value
        await quitting.value
        XCTAssertEqual(observations.writeCount, 0)
        XCTAssertNil(store.pendingChange)
        XCTAssertEqual(observations.closeCount, 1)
    }

    func testQuitDuringTheFinalOriginalCheckPreventsTheChange() async throws {
        let armed = StopRequest(), gate = OperationGate(), observations = SimulatedObservations()
        defer { gate.release() }
        let store = store(SimulatedConfiguration(beforeRead: { if armed.isRequested && $0 == 1 { gate.wait() } }), observations)
        await store.refresh()
        await store.requestClear()
        let change = try XCTUnwrap(store.pendingChange)
        armed.stop()
        let applying = Task { await store.confirm(change, saveRecovery: false) }
        try await eventually { gate.entered.isRequested }
        let quitting = Task { await store.shutdown() }
        try await eventually { store.shuttingDown }
        gate.release()
        await applying.value
        await quitting.value
        XCTAssertEqual(observations.writeCount, 0)
        XCTAssertEqual(observations.closeCount, 1)
    }

    func testACancelledQuitWaiterStillLetsACommittedChangeFinishAndVerify() async throws {
        let gate = OperationGate(), observations = SimulatedObservations(), heartbeat = StopRequest()
        defer { gate.release() }
        let store = store(SimulatedConfiguration(beforeWrite: { if $0 == 1 { gate.wait() } }), observations)
        await store.refresh()
        await store.requestClear()
        let change = try XCTUnwrap(store.pendingChange)
        let applying = Task { await store.confirm(change, saveRecovery: false) }
        try await eventually { gate.entered.isRequested }
        let quitting = Task { await store.shutdown() }
        try await eventually { store.shuttingDown }
        quitting.cancel()
        Task { heartbeat.stop() }
        try await eventually { heartbeat.isRequested }
        XCTAssertEqual(observations.closeCount, 0)
        gate.release()
        await applying.value
        await quitting.value
        XCTAssertEqual(observations.writeCount, change.items.count)
        XCTAssertEqual(observations.closeCount, 1)
        XCTAssertNil(store.notice)
    }

    func testQuitWaitsForEveryReaderAndSupportsMoreThanOneWaiter() async throws {
        let gate = OperationGate(), observations = SimulatedObservations()
        defer { gate.release() }
        let store = store(SimulatedConfiguration(beforeRead: { if $0 == 1 { gate.wait() } }), observations)
        await store.refresh()
        let files = store.files
        let first = Task {
            do { _ = try await store.readText(files[0].id); XCTFail("The first read ignored Quit") }
            catch { XCTAssertTrue(error is CancellationError) }
        }
        try await eventually { gate.entered.isRequested }
        let secondStarted = StopRequest()
        let second = Task {
            secondStarted.stop()
            do { _ = try await store.readText(files[1].id); XCTFail("The queued read ignored Quit") }
            catch { XCTAssertTrue(error is CancellationError) }
        }
        try await eventually { secondStarted.isRequested }
        let quitting = Task { await store.shutdown() }
        try await eventually { store.shuttingDown }
        let anotherStarted = StopRequest()
        let anotherWaiter = Task { anotherStarted.stop(); await store.shutdown() }
        try await eventually { anotherStarted.isRequested }
        quitting.cancel()
        gate.release()
        await first.value
        await second.value
        await quitting.value
        await anotherWaiter.value
        XCTAssertEqual(observations.closeCount, 1)
    }
}
