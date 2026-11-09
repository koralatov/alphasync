import Foundation
import XCTest
import AlphaSyncCore
@testable import AlphaSyncHardware
@testable import AlphaSyncUI

private final class EventFeed: Sendable {
    let stream: AsyncThrowingStream<Void, Error>
    let continuation: AsyncThrowingStream<Void, Error>.Continuation
    let terminated = StopRequest()
    init() {
        var saved: AsyncThrowingStream<Void, Error>.Continuation!
        stream = AsyncThrowingStream(bufferingPolicy: .bufferingNewest(1)) { saved = $0 }
        continuation = saved
        let terminated = terminated
        continuation.onTermination = { _ in terminated.stop() }
    }
    func monitor() -> AttachmentMonitor {
        let continuation = continuation
        return AttachmentMonitor(events: stream, cancel: { continuation.finish() })
    }
}

private final class EventFeeds: @unchecked Sendable {
    private let lock = NSLock()
    private var feeds: [EventFeed]
    init(_ feeds: [EventFeed]) { self.feeds = feeds }
    func next() -> AttachmentMonitor {
        lock.lock()
        defer { lock.unlock() }
        return feeds.removeFirst().monitor()
    }
}

@MainActor
final class AttachmentMonitoringTests: XCTestCase {
    private func store(_ observations: SimulatedObservations, events: @escaping @Sendable () -> AttachmentMonitor,
                       configuration: SimulatedConfiguration = SimulatedConfiguration()) -> AppStore {
        let domain = "AlphaSync-AttachmentTests-" + UUID().uuidString
        addTeardownBlock { UserDefaults(suiteName: domain)?.removePersistentDomain(forName: domain) }
        let service = DeviceService(discoveryFactory: { SimulatedDiscovery(configuration, observations) }, eventSource: events)
        return AppStore(service: service, preferences: Preferences(defaults: UserDefaults(suiteName: domain)!), monitoringEnabled: true)
    }

    private func eventually(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !condition() && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(condition(), file: file, line: line)
    }

    func testAttachmentEventsDiscoverAndRemoveDevicesAndCancelCleanly() async throws {
        let observations = SimulatedObservations(), feed = EventFeed()
        let store = store(observations, events: { feed.monitor() })
        store.start()
        feed.continuation.yield(())
        try await eventually { store.devices.count == 1 }
        let initialScans = observations.scanCount
        observations.setAttached([1, 2])
        feed.continuation.yield(())
        try await eventually { store.devices.count == 2 }
        XCTAssertGreaterThan(observations.scanCount, initialScans)
        observations.setAttached([])
        feed.continuation.yield(())
        try await eventually { store.devices.isEmpty }
        await store.shutdown()
        try await eventually { feed.terminated.isRequested }
        XCTAssertEqual(observations.closeCount, 2)
    }

    func testAnAttachmentDuringAReadIsReconciledAfterTheReadFinishes() async throws {
        let observations = SimulatedObservations(), feed = EventFeed(), reading = StopRequest()
        let gate = DispatchSemaphore(value: 0)
        defer { gate.signal() }
        let store = store(observations, events: { feed.monitor() }, configuration: SimulatedConfiguration(beforeRead: { _ in
            reading.stop(); gate.wait()
        }))
        store.start()
        feed.continuation.yield(())
        try await eventually { store.devices.count == 1 }
        let file = try XCTUnwrap(store.files.first?.id)
        let request = Task { try await store.readText(file) }
        try await eventually { reading.isRequested }
        observations.setAttached([1, 2])
        feed.continuation.yield(())
        gate.signal()
        _ = try await request.value
        try await eventually { store.devices.count == 2 }
        await store.shutdown()
    }

    func testEventsWhileAConfirmationIsOpenAreNotLost() async throws {
        let observations = SimulatedObservations(), feed = EventFeed()
        let store = store(observations, events: { feed.monitor() })
        store.start()
        feed.continuation.yield(())
        try await eventually { store.devices.count == 1 }
        store.selection = [try XCTUnwrap(store.files.first?.id)]
        await store.requestClear()
        XCTAssertNotNil(store.pendingChange)
        observations.setAttached([1, 2])
        feed.continuation.yield(())
        store.pendingChange = nil
        try await eventually { store.devices.count == 2 }
        await store.shutdown()
    }

    func testMonitorFailureRemainsVisibleUntilExplicitRestart() async throws {
        let observations = SimulatedObservations(), first = EventFeed(), second = EventFeed()
        let feeds = EventFeeds([first, second])
        let store = store(observations, events: { feeds.next() })
        store.start()
        first.continuation.yield(())
        try await eventually { store.devices.count == 1 }
        first.continuation.finish(throwing: NeoError.device("Simulated attachment monitor failure"))
        try await eventually { store.connectionIssue?.contains("monitor failure") == true }
        await store.refresh()
        observations.setAttached([])
        second.continuation.yield(())
        try await eventually { store.devices.isEmpty }
        XCTAssertNil(store.connectionIssue)
        await store.shutdown()
        try await eventually { second.terminated.isRequested }
    }
}

final class NativeAttachmentTests: XCTestCase {
    func testNativeMonitorProducesAnInitialEventAndCanBeCancelled() async throws {
        let initial = expectation(description: "Initial USB attachment event")
        let task = Task {
            let observer = NeoPresence.monitorAttachments()
            defer { observer.cancel() }
            for try await _ in observer.events { initial.fulfill(); break }
        }
        await fulfillment(of: [initial], timeout: 3)
        task.cancel()
        try await task.value
    }
}
