import Foundation
import XCTest
import AlphaSyncCore
@testable import AlphaSyncHardware
@testable import AlphaSyncUI

@MainActor
final class AppStoreTests: XCTestCase {
    private func makeStore(_ configuration: SimulatedConfiguration = SimulatedConfiguration(),
                           observations: SimulatedObservations = SimulatedObservations()) -> AppStore {
        let suite = "AlphaSync-StoreTests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let service = DeviceService(discoveryFactory: { SimulatedDiscovery(configuration, observations) })
        return AppStore(service: service, preferences: Preferences(defaults: defaults), monitoringEnabled: false)
    }

    private func temporaryFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        return folder
    }

    private func sourceFile() throws -> URL {
        let url = try temporaryFolder().appendingPathComponent("New note.txt")
        try Data("Replacement text".utf8).write(to: url)
        return url
    }

    func testReplacementKeepsTheFileChosenBeforeThePickerOpened() async throws {
        let store = makeStore()
        await store.refresh()
        let files = store.files
        XCTAssertEqual(files.count, 2)
        store.selection = [files[0].id]
        store.beginImport()
        XCTAssertTrue(store.showImporter)
        store.selection = [files[1].id]
        // SwiftUI may dismiss the panel before delivering its result.
        store.showImporter = false
        await store.finishImport(.success([try sourceFile()]))?.value
        XCTAssertEqual(store.pendingChange?.items.first?.file.id, files[0].id)
        await store.shutdown()
    }

    func testAddingAFileKeepsTheOriginalNeoAfterTheSidebarChanges() async throws {
        let observations = SimulatedObservations()
        observations.setAttached([1, 2])
        let store = makeStore(observations: observations)
        await store.refresh()
        let original = store.devices[0].connection
        let other = store.devices[1].connection
        store.sidebar = .applet(original, NeoApplet.alphaWord)
        store.beginImport()
        store.sidebar = .applet(other, NeoApplet.alphaWord)
        await store.finishImport(.success([try sourceFile()]))?.value
        XCTAssertEqual(store.devices.first { $0.connection == original }?.applets.first?.files.count, 3)
        XCTAssertEqual(store.devices.first { $0.connection == other }?.applets.first?.files.count, 2)
        XCTAssertEqual(observations.writeCount, 1)
        await store.shutdown()
    }

    func testExportKeepsTheFilesChosenBeforeTheFolderPickerOpened() async throws {
        let store = makeStore()
        await store.refresh()
        let files = store.files
        store.selection = [files[0].id]
        store.beginExport()
        store.selection = [files[1].id]
        store.showExportFolder = false
        let folder = try temporaryFolder()
        await store.finishExport(.success(folder))?.value
        let outputs = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        XCTAssertEqual(outputs.count, 1)
        XCTAssertEqual(try String(contentsOf: XCTUnwrap(outputs.first), encoding: .utf8), "Original 1")
        await store.shutdown()
    }

    func testImportDoesNotUseAReconnectedNeoAfterThePickerOpened() async throws {
        let observations = SimulatedObservations()
        let store = makeStore(observations: observations)
        await store.refresh()
        store.beginImport()
        let original = store.chosenDevice?.connection
        observations.setAttached([])
        await store.refresh()
        observations.setAttached([1])
        await store.refresh()
        XCTAssertNotEqual(store.chosenDevice?.connection, original)
        await store.finishImport(.success([try sourceFile()]))?.value
        XCTAssertEqual(observations.writeCount, 0)
        XCTAssertNil(store.pendingChange)
        XCTAssertNotNil(store.notice)
        await store.shutdown()
    }

    func testExportDoesNotUseAReconnectedNeoAfterThePickerOpened() async throws {
        let observations = SimulatedObservations()
        let store = makeStore(observations: observations)
        await store.refresh()
        store.beginExport()
        observations.setAttached([])
        await store.refresh()
        observations.setAttached([1])
        await store.refresh()
        let folder = try temporaryFolder()
        await store.finishExport(.success(folder))?.value
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
        XCTAssertNotNil(store.notice)
        await store.shutdown()
    }

    func testCancelledPickerDiscardsItsRequest() async throws {
        let store = makeStore()
        await store.refresh()
        store.selection = [store.files[0].id]
        store.beginImport()
        XCTAssertNil(store.finishImport(.failure(CocoaError(.userCancelled))))
        XCTAssertNil(store.finishImport(.success([try sourceFile()])))
        XCTAssertNil(store.notice)
        let nextFile = store.files[1].id
        store.selection = [nextFile]
        store.beginImport()
        await store.finishImport(.success([try sourceFile()]))?.value
        XCTAssertEqual(store.pendingChange?.items.first?.file.id, nextFile)
        await store.shutdown()
    }

    func testRowDropCapturesItsFileBeforeTheTaskStarts() async throws {
        let store = makeStore()
        await store.refresh()
        let original = store.files[0].id
        let task = store.importDroppedFiles([try sourceFile()], replacing: original)
        store.selection = [store.files[1].id]
        await task?.value
        XCTAssertEqual(store.pendingChange?.items.first?.file.id, original)
        await store.shutdown()
    }

    func testReplacementInvalidatesPreviewWithTheSameFileIdentityAndSize() async throws {
        let store = makeStore()
        await store.refresh()
        let file = store.files[0]
        store.selection = [file.id]
        let previous = try XCTUnwrap(store.inspectorPreviewID)
        store.beginImport()
        await store.finishImport(.success([try sourceFile()]))?.value
        let change = try XCTUnwrap(store.pendingChange)
        await store.confirm(change, saveRecovery: false)
        let current = try XCTUnwrap(store.inspectorPreviewID)
        XCTAssertEqual(current.file, previous.file)
        XCTAssertEqual(store.selectedFiles.first?.size, file.size)
        XCTAssertNotEqual(current, previous)
        let text = try await store.readText(current.file)
        XCTAssertEqual(text, "Replacement text")
        await store.shutdown()
    }

    func testClearInvalidatesTheSelectedFilePreview() async throws {
        let store = makeStore()
        await store.refresh()
        store.selection = [store.files[0].id]
        let previous = try XCTUnwrap(store.inspectorPreviewID)
        await store.requestClear()
        let change = try XCTUnwrap(store.pendingChange)
        await store.confirm(change, saveRecovery: false)
        let current = try XCTUnwrap(store.inspectorPreviewID)
        XCTAssertEqual(current.file, previous.file)
        XCTAssertNotEqual(current, previous)
        let text = try await store.readText(current.file)
        XCTAssertEqual(text, "")
        await store.shutdown()
    }

    func testExplicitRefreshInvalidatesPreviewWithoutChangingSelection() async throws {
        let store = makeStore()
        await store.refresh()
        store.selection = [store.files[0].id]
        let previous = try XCTUnwrap(store.inspectorPreviewID)
        store.reconcileSelection()
        XCTAssertEqual(store.inspectorPreviewID, previous)
        await store.refresh()
        XCTAssertEqual(store.inspectorPreviewID?.file, previous.file)
        XCTAssertNotEqual(store.inspectorPreviewID, previous)
        await store.shutdown()
    }

    func testPartialExportReportsAndRetainsTheSavedFiles() async throws {
        let store = makeStore(SimulatedConfiguration(failingRead: 2))
        await store.refresh()
        store.beginExport()
        let folder = try temporaryFolder()
        await store.finishExport(.success(folder))?.value
        XCTAssertEqual(store.lastExportedFiles.count, 1)
        let saved = try XCTUnwrap(store.lastExportedFiles.first)
        XCTAssertEqual(try String(contentsOf: saved, encoding: .utf8), "Original 1")
        let message = try XCTUnwrap(store.notice?.message)
        XCTAssertTrue(message.contains("1 of 2 files"))
        XCTAssertTrue(message.contains(folder.path))
        XCTAssertTrue(message.contains("The saved files have been kept."))
        await store.shutdown()
    }

    func testErrorRecoveryDoesNotRetryModeSwitchFailures() async throws {
        let observations = SimulatedObservations()
        let store = makeStore(SimulatedConfiguration(failingRead: 2), observations: observations)
        await store.refresh()
        store.beginExport()
        await store.finishExport(.success(try temporaryFolder()))?.value
        XCTAssertEqual(observations.modeSwitchRetries, [true, false])
        await store.refresh()
        XCTAssertEqual(observations.modeSwitchRetries, [true, false, true])
        await store.shutdown()
    }

    private func dictionarySource(_ text: String) throws -> URL {
        let url = try temporaryFolder().appendingPathComponent("Dictionary.txt")
        try Data(text.utf8).write(to: url)
        return url
    }

    func testDictionaryOmissionsNeedReviewBeforeTheReplaceConfirmation() async throws {
        let observations = SimulatedObservations()
        let store = makeStore(SimulatedConfiguration(appletID: NeoApplet.dictionary), observations: observations)
        await store.refresh()
        let file = store.files[0].id
        store.selection = [file]
        store.beginImport()
        await store.finishImport(.success([try dictionarySource("cats a")]))?.value
        let warning = try XCTUnwrap(store.pendingDictionaryImport)
        XCTAssertEqual(warning.report.omittedWords, 1)
        XCTAssertNil(store.pendingChange)
        XCTAssertEqual(observations.writeCount, 0)
        await store.confirmDictionaryImport(warning)
        let replacement = try XCTUnwrap(store.pendingChange)
        XCTAssertEqual(observations.writeCount, 0)
        await store.confirm(replacement, saveRecovery: false)
        XCTAssertEqual(observations.writeCount, 1)
        let text = try await store.readText(file)
        XCTAssertEqual(text, "cats")
        await store.shutdown()
    }

    func testChangedDictionarySourceNeedsANewOmissionReview() async throws {
        let observations = SimulatedObservations()
        let store = makeStore(SimulatedConfiguration(appletID: NeoApplet.dictionary), observations: observations)
        await store.refresh()
        store.selection = [store.files[0].id]
        let source = try dictionarySource("cats a")
        store.beginImport()
        await store.finishImport(.success([source]))?.value
        let warning = try XCTUnwrap(store.pendingDictionaryImport)
        try Data("dogs a".utf8).write(to: source)
        await store.confirmDictionaryImport(warning)
        XCTAssertEqual(store.pendingDictionaryImport?.sourceText, "dogs a")
        XCTAssertNil(store.pendingChange)
        XCTAssertEqual(observations.writeCount, 0)
        await store.shutdown()
    }

    func testDictionaryWithoutUsableWordsIsRejectedBeforeWriting() async throws {
        let observations = SimulatedObservations()
        let store = makeStore(SimulatedConfiguration(appletID: NeoApplet.dictionary), observations: observations)
        await store.refresh()
        store.selection = [store.files[0].id]
        store.beginImport()
        await store.finishImport(.success([try dictionarySource("a extraordinarilylongword")]))?.value
        XCTAssertEqual(observations.writeCount, 0)
        XCTAssertNil(store.pendingDictionaryImport)
        XCTAssertNil(store.pendingChange)
        XCTAssertNotNil(store.notice)
        await store.shutdown()
    }

    func testCancellingADictionaryWarningRetainsEarlierAddedFiles() async throws {
        let observations = SimulatedObservations()
        let store = makeStore(SimulatedConfiguration(appletID: NeoApplet.dictionary), observations: observations)
        await store.refresh()
        store.beginImport()
        await store.finishImport(.success([try dictionarySource("cats"), try dictionarySource("dogs a")]))?.value
        let warning = try XCTUnwrap(store.pendingDictionaryImport)
        XCTAssertEqual(warning.completedFiles, 1)
        store.cancelDictionaryImport(warning)
        XCTAssertEqual(observations.writeCount, 1)
        XCTAssertEqual(store.files.count, 3)
        XCTAssertNil(store.pendingDictionaryImport)
        XCTAssertTrue(try XCTUnwrap(store.notice?.message).contains("already added and verified"))
        await store.shutdown()
    }

    func testDictionaryBatchResumesWithoutAddingEarlierFilesAgain() async throws {
        let observations = SimulatedObservations()
        let store = makeStore(SimulatedConfiguration(appletID: NeoApplet.dictionary), observations: observations)
        await store.refresh()
        store.beginImport()
        await store.finishImport(.success([try dictionarySource("cats"), try dictionarySource("dogs a"), try dictionarySource("birds")]))?.value
        let warning = try XCTUnwrap(store.pendingDictionaryImport)
        await store.confirmDictionaryImport(warning)
        XCTAssertEqual(observations.writeCount, 3)
        XCTAssertEqual(store.files.count, 5)
        XCTAssertNil(store.pendingDictionaryImport)
        await store.shutdown()
    }
}
