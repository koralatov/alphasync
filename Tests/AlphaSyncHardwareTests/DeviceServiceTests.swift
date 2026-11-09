import Foundation
import XCTest
import AlphaSyncCore
@testable import AlphaSyncHardware

final class DeviceServiceTests: XCTestCase {
    private func makeService(_ configuration: SimulatedConfiguration = SimulatedConfiguration(),
                         observations: SimulatedObservations) -> DeviceService {
        DeviceService(discoveryFactory: { SimulatedDiscovery(configuration, observations) })
    }

    private func device(_ service: DeviceService) async throws -> NeoSnapshot {
        let result = try await service.scan()
        return try XCTUnwrap(result.devices.first)
    }

    private func temporaryFolder() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        return root
    }

    func testReconnectionRejectsRequestsForTheOldConnection() async throws {
        let observations = SimulatedObservations()
        let service = makeService(observations: observations)
        let original = try await device(service)
        let file = try XCTUnwrap(original.applets.first?.files.first)

        observations.setAttached([])
        _ = try await service.scan()
        XCTAssertEqual(observations.closeCount, 1)
        observations.setAttached([1])
        let reconnected = try await device(service)
        XCTAssertNotEqual(original.connection, reconnected.connection)
        do {
            _ = try await service.read(file.id)
            XCTFail("A stale request reached the replacement connection")
        } catch {
            XCTAssertEqual(error as? NeoError, .disconnected)
        }
        XCTAssertEqual(observations.writeCount, 0)
        await service.shutdown()
    }

    func testFailedRecoveryPreventsEveryWrite() async throws {
        let observations = SimulatedObservations()
        let service = makeService(observations: observations)
        let snapshot = try await device(service)
        let change = try await service.prepareClear(connection: snapshot.connection, appletID: NeoApplet.alphaWord, files: nil)
        let root = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let blocked = root.appendingPathComponent("A regular file")
        try Data([1]).write(to: blocked)
        do {
            _ = try await service.apply(change, recovery: RecoveryOptions(enabled: true, folder: blocked, retentionDays: 0))
            XCTFail("A failed requested recovery copy allowed writing")
        } catch {
            let failure = try XCTUnwrap(error as? OperationFailure)
            XCTAssertEqual(failure.completedFiles, 0)
            XCTAssertFalse(failure.currentFileMayHaveChanged)
        }
        XCTAssertEqual(observations.writeCount, 0)
        let original = try await service.read(change.items[0].file.id)
        XCTAssertEqual(original, change.items[0].original)
        await service.shutdown()
    }

    func testPartialClearKeepsAllRecoveryCopiesAndAccurateOutcome() async throws {
        let observations = SimulatedObservations()
        let configuration = SimulatedConfiguration(failingWriteNumber: 2)
        let service = makeService(configuration, observations: observations)
        let snapshot = try await device(service)
        let change = try await service.prepareClear(connection: snapshot.connection, appletID: NeoApplet.alphaWord, files: nil)
        let root = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        do {
            _ = try await service.apply(change, recovery: RecoveryOptions(enabled: true, folder: root, retentionDays: 0))
            XCTFail("A simulated verification failure unexpectedly succeeded")
        } catch {
            let failure = try XCTUnwrap(error as? OperationFailure)
            XCTAssertEqual(failure.completedFiles, 1)
            XCTAssertTrue(failure.currentFileMayHaveChanged)
            let folder = try XCTUnwrap(failure.recoveryFolder)
            for item in change.items {
                let raw = folder.appendingPathComponent(item.file.displayName + ".neo")
                XCTAssertEqual(try Data(contentsOf: raw), item.original)
            }
            XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent(".recovery-information.plist").path))
        }
        XCTAssertEqual(observations.writeCount, 2)
        await service.shutdown()
    }

    func testCreationRemainsCountedWhenRefreshingItsListFails() async throws {
        let observations = SimulatedObservations()
        let service = makeService(SimulatedConfiguration(failRefreshAfterWriting: true), observations: observations)
        let snapshot = try await device(service)
        let root = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Added.txt")
        try Data("A new note".utf8).write(to: source)
        do {
            _ = try await service.create(connection: snapshot.connection, appletID: NeoApplet.alphaWord, from: source)
            XCTFail("The simulated refresh failure unexpectedly succeeded")
        } catch {
            let failure = try XCTUnwrap(error as? OperationFailure)
            XCTAssertEqual(failure.completedFiles, 1)
            XCTAssertFalse(failure.currentFileMayHaveChanged)
        }
        XCTAssertEqual(observations.writeCount, 1)
        await service.shutdown()
    }

    func testOneFailedBackupFileLeavesAnIncompleteFolderAndLog() async throws {
        let observations = SimulatedObservations()
        let service = makeService(SimulatedConfiguration(failingRead: 2), observations: observations)
        let snapshot = try await device(service)
        let root = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let result = try await service.backup(connections: [snapshot.connection], includedApplets: nil,
                                              destination: root, saveLog: true, stop: StopRequest(), progress: { _ in })
        XCTAssertEqual(result.saved, 1)
        XCTAssertEqual(result.expected, 2)
        XCTAssertFalse(result.complete)
        let folder = try XCTUnwrap(result.folders.first)
        XCTAssertTrue(folder.lastPathComponent.hasSuffix(AtomicFileStore.incompleteSuffix))
        let bytes = try Data(contentsOf: folder.appendingPathComponent("AlphaSync Backup Log.plist"))
        let log = try XCTUnwrap(PropertyListSerialization.propertyList(from: bytes, format: nil) as? [String: Any])
        XCTAssertEqual(log["status"] as? String, "incomplete")
        let text = try String(contentsOf: folder.appendingPathComponent("AlphaWord/File 1.txt"), encoding: .utf8)
        XCTAssertEqual(text, "Original 1")
        await service.shutdown()
    }

    func testStoppingBackupRetainsItsFirstFileAndMarksTheFolderIncomplete() async throws {
        let observations = SimulatedObservations()
        let service = makeService(observations: observations)
        let snapshot = try await device(service)
        let root = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let stop = StopRequest()
        let result = try await service.backup(connections: [snapshot.connection], includedApplets: nil,
                                              destination: root, saveLog: false, stop: stop) { value in
            if !value.fileName.isEmpty { stop.stop() }
        }
        XCTAssertEqual(result.saved, 1)
        XCTAssertTrue(result.stopped)
        XCTAssertFalse(result.complete)
        let folder = try XCTUnwrap(result.folders.first)
        XCTAssertTrue(folder.lastPathComponent.hasSuffix(AtomicFileStore.incompleteSuffix))
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("AlphaWord/File 1.txt").path))
        await service.shutdown()
    }

    func testPartialExportRetainsSavedURLsAndTheUnderlyingFailure() async throws {
        let service = makeService(SimulatedConfiguration(failingRead: 2), observations: SimulatedObservations())
        let snapshot = try await device(service)
        let files = try XCTUnwrap(snapshot.applets.first?.files)
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        do {
            _ = try await service.export(files.map(\.id), to: folder)
            XCTFail("The simulated export failure unexpectedly succeeded")
        } catch {
            let failure = try XCTUnwrap(error as? ExportFailure)
            XCTAssertEqual(failure.completedFiles, 1)
            XCTAssertEqual(failure.expectedFiles, 2)
            XCTAssertEqual(failure.destination, folder)
            XCTAssertEqual(failure.underlying as? NeoError, .device("Simulated read failure"))
            let saved = try XCTUnwrap(failure.savedFiles.first)
            XCTAssertEqual(try String(contentsOf: saved, encoding: .utf8), "Original 1")
        }
        await service.shutdown()
    }

    func testCancellationAfterAnExportKeepsItsCompletedFile() async throws {
        let reachedSecond = expectation(description: "Second file read started")
        let gate = DispatchSemaphore(value: 0)
        defer { gate.signal() }
        let configuration = SimulatedConfiguration(beforeRead: { index in
            if index == 2 { reachedSecond.fulfill(); gate.wait() }
        })
        let service = makeService(configuration, observations: SimulatedObservations())
        let snapshot = try await device(service)
        let files = try XCTUnwrap(snapshot.applets.first?.files)
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let task = Task { try await service.export(files.map(\.id), to: folder) }
        await fulfillment(of: [reachedSecond], timeout: 3)
        task.cancel()
        gate.signal()
        do {
            _ = try await task.value
            XCTFail("The cancelled export unexpectedly succeeded")
        } catch {
            let failure = try XCTUnwrap(error as? ExportFailure)
            XCTAssertTrue(failure.underlying is CancellationError)
            XCTAssertEqual(failure.completedFiles, 1)
            let saved = try XCTUnwrap(failure.savedFiles.first)
            XCTAssertEqual(try String(contentsOf: saved, encoding: .utf8), "Original 1")
            XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("File 2.txt").path))
        }
        await service.shutdown()
    }
}
