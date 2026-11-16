import Foundation
import XCTest
import AlphaSyncCore
@testable import AlphaSyncHardware

final class ChangeTargetTests: XCTestCase {
    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func source() throws -> URL {
        let url = try folder().appendingPathComponent("Replacement.txt")
        try Data("Replacement text".utf8).write(to: url)
        return url
    }

    func testReplacementRejectsARenamedTargetEvenWhenItsTextIsUnchanged() async throws {
        let observations = SimulatedObservations()
        let service = DeviceService(discoveryFactory: { SimulatedDiscovery(SimulatedConfiguration(), observations) })
        let discovery = try await service.scan()
        let snapshot = try XCTUnwrap(discovery.devices.first)
        let file = try XCTUnwrap(snapshot.applets.first?.files.first)
        let change = try await service.prepareReplacement(file: file.id, from: source())
        _ = try await service.rename(file.id, to: "Renamed")
        let writesBeforeConfirmation = observations.writeCount
        let destination = try folder()
        do {
            _ = try await service.apply(change, recovery: RecoveryOptions(enabled: true, folder: destination, retentionDays: 0))
            XCTFail("A renamed file was changed using an old confirmation")
        } catch {
            let failure = try XCTUnwrap(error as? OperationFailure)
            XCTAssertEqual(failure.completedFiles, 0)
            XCTAssertFalse(failure.currentFileMayHaveChanged)
            XCTAssertTrue(failure.localizedDescription.contains("details changed"))
        }
        XCTAssertEqual(observations.writeCount, writesBeforeConfirmation)
        let contents = try await service.read(file.id)
        XCTAssertEqual(contents, change.items[0].original)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: destination.path).isEmpty)
        await service.shutdown()
    }

    func testClearChecksEveryNamedTargetBeforeChangingTheFirstFile() async throws {
        let observations = SimulatedObservations()
        let service = DeviceService(discoveryFactory: { SimulatedDiscovery(SimulatedConfiguration(), observations) })
        let discovery = try await service.scan()
        let snapshot = try XCTUnwrap(discovery.devices.first)
        let change = try await service.prepareClear(connection: snapshot.connection, appletID: NeoApplet.alphaWord, files: nil)
        let last = try XCTUnwrap(change.items.last)
        _ = try await service.rename(last.file.id, to: "Different")
        let writesBeforeConfirmation = observations.writeCount
        do {
            _ = try await service.apply(change, recovery: RecoveryOptions(enabled: false, folder: try folder(), retentionDays: 0))
            XCTFail("A changed target was accepted during a multi-file clear")
        } catch {
            let failure = try XCTUnwrap(error as? OperationFailure)
            XCTAssertEqual(failure.completedFiles, 0)
            XCTAssertFalse(failure.currentFileMayHaveChanged)
        }
        XCTAssertEqual(observations.writeCount, writesBeforeConfirmation)
        for item in change.items {
            let contents = try await service.read(item.file.id)
            XCTAssertEqual(contents, item.original)
        }
        await service.shutdown()
    }

    func testRenamingReadOnlyAppletDataNeverReachesTheDeviceWrite() async throws {
        let observations = SimulatedObservations()
        let configuration = SimulatedConfiguration(appletID: 0xb000)
        let service = DeviceService(discoveryFactory: { SimulatedDiscovery(configuration, observations) })
        let discovery = try await service.scan()
        let snapshot = try XCTUnwrap(discovery.devices.first)
        let file = try XCTUnwrap(snapshot.applets.first?.files.first)
        do {
            _ = try await service.rename(file.id, to: "Renamed")
            XCTFail("Read-only applet data was renamed")
        } catch {
            let failure = try XCTUnwrap(error as? OperationFailure)
            XCTAssertFalse(failure.currentFileMayHaveChanged)
            XCTAssertTrue(failure.localizedDescription.contains("cannot be renamed"))
        }
        XCTAssertEqual(observations.writeCount, 0)
        await service.shutdown()
    }

    func testRenamingAnUnlistedFileStopsBeforeDeviceAccess() async throws {
        let observations = SimulatedObservations()
        let service = DeviceService(discoveryFactory: { SimulatedDiscovery(SimulatedConfiguration(), observations) })
        let discovery = try await service.scan()
        let snapshot = try XCTUnwrap(discovery.devices.first)
        let missing = NeoFileID(connection: snapshot.connection, applet: NeoApplet.alphaWord, index: 200)
        do {
            _ = try await service.rename(missing, to: "Renamed")
            XCTFail("An unlisted file was renamed")
        } catch {
            let failure = try XCTUnwrap(error as? OperationFailure)
            XCTAssertEqual(failure.underlying as? NeoError, .disconnected)
            XCTAssertFalse(failure.currentFileMayHaveChanged)
        }
        XCTAssertEqual(observations.writeCount, 0)
        await service.shutdown()
    }
}
