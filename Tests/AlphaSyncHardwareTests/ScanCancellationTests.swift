import Foundation
import XCTest
import AlphaSyncCore
@testable import AlphaSyncHardware

private final class ScanGate: Sendable {
    let entered = StopRequest()
    let semaphore = DispatchSemaphore(value: 0)
    func wait() { entered.stop(); semaphore.wait() }
    func release() { semaphore.signal() }
}

final class ScanCancellationTests: XCTestCase {
    private func waitForEntry(_ gate: ScanGate) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !gate.entered.isRequested && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(gate.entered.isRequested)
    }

    func testCancelledOpeningClosesTheUnpublishedHandleAndSkipsTheNextDevice() async throws {
        let gate = ScanGate(), observations = SimulatedObservations()
        defer { gate.release() }
        observations.setAttached([1, 2])
        let configuration = SimulatedConfiguration(beforeSnapshot: { _ in if !gate.entered.isRequested { gate.wait() } })
        let service = DeviceService(discoveryFactory: { SimulatedDiscovery(configuration, observations) })
        let scanning = Task { try await service.scan() }
        try await waitForEntry(gate)
        scanning.cancel(); gate.release()
        do { _ = try await scanning.value; XCTFail("The cancelled inventory was published") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(observations.openCount, 1)
        XCTAssertEqual(observations.closeCount, 1)
        let retried = try await service.scan()
        XCTAssertEqual(retried.devices.count, 2)
        XCTAssertEqual(observations.openCount, 3)
        XCTAssertEqual(observations.writeCount, 0)
        await service.shutdown()
    }

    func testCancelledRefreshPreservesTheHealthyConnectionAndDoesNotRecordAFailure() async throws {
        let gate = ScanGate(), observations = SimulatedObservations()
        defer { gate.release() }
        let configuration = SimulatedConfiguration(beforeSnapshot: { if $0 == 2 { gate.wait() } })
        let service = DeviceService(discoveryFactory: { SimulatedDiscovery(configuration, observations) })
        let original = try await service.scan()
        let refreshing = Task { try await service.refresh(retryConnections: true) }
        try await waitForEntry(gate)
        refreshing.cancel(); gate.release()
        do { _ = try await refreshing.value; XCTFail("The cancelled refresh succeeded") }
        catch { XCTAssertTrue(error is CancellationError) }
        let retained = try await service.scan()
        XCTAssertEqual(retained.devices.first?.connection, original.devices.first?.connection)
        XCTAssertNil(retained.issue)
        XCTAssertEqual(observations.openCount, 1)
        XCTAssertEqual(observations.closeCount, 0)
        await service.shutdown()
    }

    func testStoppingBackupDuringInitialInventoryCreatesNoFoldersOrFalseCompletion() async throws {
        let stop = StopRequest(), observations = SimulatedObservations()
        let configuration = SimulatedConfiguration(beforeSnapshot: { if $0 == 2 { stop.stop() } })
        let service = DeviceService(discoveryFactory: { SimulatedDiscovery(configuration, observations) })
        let scanned = try await service.scan()
        let snapshot = try XCTUnwrap(scanned.devices.first)
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: destination) }
        let result = try await service.backup(connections: [snapshot.connection], includedApplets: nil,
            destination: destination, saveLog: true, stop: stop, progress: { _ in })
        XCTAssertTrue(result.stopped)
        XCTAssertFalse(result.complete)
        XCTAssertEqual(result.saved, 0)
        XCTAssertTrue(result.folders.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertEqual(observations.writeCount, 0)
        await service.shutdown()
    }
}
