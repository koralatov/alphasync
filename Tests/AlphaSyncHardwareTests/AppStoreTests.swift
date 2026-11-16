import Foundation
import XCTest
import AlphaSyncCore
@testable import AlphaSyncHardware
@testable import AlphaSyncUI

@MainActor
final class AppStoreTests: XCTestCase {
    func testAFileListRefreshAfterRenameKeepsItsSelectionAndNewSortOrder() async throws {
        let store = makeStore()
        await store.refresh()
        let file = try XCTUnwrap(store.files.first)
        store.selection = [file.id]
        await store.rename(file.id, to: "Zed")
        XCTAssertEqual(store.files.map(\.displayName), ["File 2", "Zed"])
        XCTAssertEqual(store.selectedFiles.map(\.id), [file.id])
        XCTAssertEqual(store.selectedFiles.first?.displayName, "Zed")
        await store.shutdown()
    }

    func testFileListsFollowFilterAndSidebarChanges() async throws {
        let observations = SimulatedObservations()
        observations.setAttached([1, 2])
        let store = makeStore(observations: observations)
        await store.refresh()
        let first = try XCTUnwrap(store.devices.first)
        let second = store.devices[1]
        var header = Data(repeating: 0, count: NeoApplet.headerSize)
        header.replaceSubrange(0..<4, with: [0xc0, 0xff, 0xee, 0xad])
        header[20] = 0xa0; header[21] = 5
        var dictionary = try NeoApplet(header: header)
        dictionary.files = [NeoFile(id: NeoFileID(connection: first.connection, applet: dictionary.id, index: 1),
            attributes: try NeoFileAttributes(name: "Dictionary"), size: 512)]
        store.devices[0] = NeoSnapshot(connection: first.connection, registryID: first.registryID,
            systemVersion: first.systemVersion, availableRAM: first.availableRAM, availableROM: first.availableROM,
            applets: first.applets + [dictionary])
        store.sidebar = .device(first.connection)
        store.preferences.filter = .alphaWord
        XCTAssertEqual(store.files.map(\.displayName), ["File 1", "File 2"])
        store.preferences.filter = .textApplets
        XCTAssertEqual(store.files.map(\.displayName), ["Dictionary", "File 1", "File 2"])
        store.sidebar = .applet(first.connection, dictionary.id)
        XCTAssertEqual(store.files.map(\.displayName), ["Dictionary"])
        store.preferences.filter = .alphaWord
        store.reconcileSelection()
        XCTAssertEqual(store.files.map(\.displayName), ["File 1", "File 2"])
        store.sidebar = .device(second.connection)
        XCTAssertTrue(store.files.allSatisfy { $0.id.connection == second.connection })
        store.sidebar = .device(first.connection)
        XCTAssertTrue(store.files.allSatisfy { $0.id.connection == first.connection })
        await store.shutdown()
    }

    func testAFileListDiscardsDisconnectedFilesAndUsesTheNewConnectionIdentity() async throws {
        let observations = SimulatedObservations()
        let store = makeStore(observations: observations)
        await store.refresh()
        let original = try XCTUnwrap(store.files.first?.id)
        store.selection = [original]
        observations.setAttached([])
        await store.refresh()
        XCTAssertTrue(store.files.isEmpty)
        XCTAssertTrue(store.selectedFiles.isEmpty)
        XCTAssertTrue(store.selection.isEmpty)
        observations.setAttached([1])
        await store.refresh()
        XCTAssertEqual(store.files.count, 2)
        XCTAssertNotEqual(store.files.first?.id.connection, original.connection)
        XCTAssertTrue(store.selection.isEmpty)
        await store.shutdown()
    }

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

    func testClearAllRequiresANonemptyAppletRatherThanADeviceScope() async throws {
        for configuration in [SimulatedConfiguration(), SimulatedConfiguration(fileCount: 0)] {
            let observations = SimulatedObservations()
            let store = makeStore(configuration, observations: observations)
            await store.refresh()
            XCTAssertEqual(store.canClear, configuration.fileCount > 0)
            store.sidebar = .device(try XCTUnwrap(store.devices.first?.connection))
            XCTAssertFalse(store.canClear)
            await store.requestClear()
            XCTAssertNil(store.pendingChange)
            XCTAssertEqual(observations.writeCount, 0)
            await store.shutdown()
        }
    }

    func testClearRejectsReadOnlyAppletAndFileSelections() async throws {
        let observations = SimulatedObservations()
        let store = makeStore(SimulatedConfiguration(appletID: 0xa001), observations: observations)
        await store.refresh()
        XCTAssertFalse(store.canClear)
        store.selection = [try XCTUnwrap(store.files.first?.id)]
        XCTAssertFalse(store.canClear)
        await store.requestClear()
        XCTAssertNil(store.pendingChange)
        XCTAssertEqual(observations.writeCount, 0)
        await store.shutdown()
    }

    func testClearRejectsMissingOrReconnectedSelectedIDs() async throws {
        let observations = SimulatedObservations()
        let store = makeStore(observations: observations)
        await store.refresh()
        let file = try XCTUnwrap(store.files.first?.id)
        let missing = NeoFileID(connection: file.connection, applet: file.applet, index: 99)
        store.selection = [file, missing]
        XCTAssertFalse(store.canClear)
        await store.requestClear()
        let previousConnection = NeoFileID(connection: UUID(), applet: file.applet, index: file.index)
        store.selection = [previousConnection]
        XCTAssertFalse(store.canClear)
        await store.requestClear()
        XCTAssertNil(store.pendingChange)
        XCTAssertEqual(observations.writeCount, 0)
        await store.shutdown()
    }

    func testClearStaysUnavailableDuringAConfirmationAndShutdown() async throws {
        let observations = SimulatedObservations()
        let store = makeStore(observations: observations)
        await store.refresh()
        XCTAssertTrue(store.canClear)
        await store.requestClear()
        XCTAssertNotNil(store.pendingChange)
        XCTAssertFalse(store.canClear)
        XCTAssertFalse(store.isPerformingOperation)
        await store.shutdown()
        store.pendingChange = nil
        XCTAssertFalse(store.canClear)
        XCTAssertEqual(observations.writeCount, 0)
    }

    func testClearRejectsAMixedWritableAppletSelectionWithoutAConfirmationOrWrite() async throws {
        let observations = SimulatedObservations()
        let store = makeStore(observations: observations)
        // The extra applet is UI snapshot data; no device write is needed to construct it.
        await store.refresh()
        let original = try XCTUnwrap(store.devices.first)
        var header = Data(repeating: 0, count: NeoApplet.headerSize)
        header.replaceSubrange(0..<4, with: [0xc0, 0xff, 0xee, 0xad])
        header[20] = 0xa0; header[21] = 5
        var dictionary = try NeoApplet(header: header)
        dictionary.files = [NeoFile(id: NeoFileID(connection: original.connection, applet: dictionary.id, index: 1),
            attributes: try NeoFileAttributes(name: "Dictionary"), size: 512)]
        store.devices = [NeoSnapshot(connection: original.connection, registryID: original.registryID,
            systemVersion: original.systemVersion, availableRAM: original.availableRAM, availableROM: original.availableROM,
            applets: original.applets + [dictionary])]
        store.sidebar = .device(original.connection)
        store.selection = [try XCTUnwrap(original.applets.first?.files.first?.id), dictionary.files[0].id]
        XCTAssertEqual(store.selectedFiles.count, 2)
        XCTAssertFalse(store.canClear)
        await store.requestClear()
        XCTAssertNil(store.pendingChange)
        XCTAssertNil(store.notice)
        XCTAssertEqual(observations.writeCount, 0)
        await store.shutdown()
    }

    func testClearStillPreparesASelectionFromOneWritableApplet() async throws {
        let observations = SimulatedObservations()
        let store = makeStore(observations: observations)
        await store.refresh()
        store.selection = Set(store.files.map(\.id))
        XCTAssertEqual(store.selectedFiles.count, 2)
        XCTAssertTrue(store.canClear)
        await store.requestClear()
        XCTAssertEqual(store.pendingChange?.items.count, 2)
        XCTAssertEqual(observations.writeCount, 0)
        await store.shutdown()
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

    func testFailedOperationRecoveryInvalidatesAnUnchangedSelectedPreview() async throws {
        let observations = SimulatedObservations()
        let store = makeStore(observations: observations)
        await store.refresh()
        let selected = store.files[0]
        store.selection = [selected.id]
        let previous = try XCTUnwrap(store.inspectorPreviewID)
        await store.rename(store.files[1].id, to: "\n")
        let current = try XCTUnwrap(store.inspectorPreviewID)
        XCTAssertEqual(current.file, previous.file)
        XCTAssertNotEqual(current, previous)
        XCTAssertEqual(store.selectedFiles, [selected])
        XCTAssertNotNil(store.notice)
        XCTAssertEqual(observations.writeCount, 0)
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

    func testRepeatedReplacementConfirmationDoesNotWriteOrReportAnErrorAgain() async throws {
        let observations = SimulatedObservations()
        let store = makeStore(observations: observations)
        await store.refresh()
        store.selection = [try XCTUnwrap(store.files.first?.id)]
        store.beginImport()
        await store.finishImport(.success([try sourceFile()]))?.value
        let change = try XCTUnwrap(store.pendingChange)
        await store.confirm(change, saveRecovery: false)
        XCTAssertEqual(observations.writeCount, 1)
        XCTAssertNil(store.pendingChange)
        XCTAssertNil(store.notice)
        await store.confirm(change, saveRecovery: false)
        XCTAssertEqual(observations.writeCount, 1)
        XCTAssertNil(store.notice)
        await store.shutdown()
    }

    func testAnOldChangeCannotConfirmOrCancelANewerWarning() async throws {
        let observations = SimulatedObservations()
        let store = makeStore(observations: observations)
        await store.refresh()
        await store.requestClear()
        let first = try XCTUnwrap(store.pendingChange)
        store.cancel(first)
        await store.requestClear()
        let current = try XCTUnwrap(store.pendingChange)
        XCTAssertNotEqual(first.id, current.id)
        await store.confirm(first, saveRecovery: false)
        store.cancel(first)
        XCTAssertEqual(store.pendingChange?.id, current.id)
        XCTAssertNil(store.notice)
        XCTAssertEqual(observations.writeCount, 0)
        store.cancel(current)
        XCTAssertNil(store.pendingChange)
        await store.shutdown()
    }

    func testAnOldDictionaryWarningCannotDismissItsReplacement() async throws {
        let observations = SimulatedObservations()
        let store = makeStore(SimulatedConfiguration(appletID: NeoApplet.dictionary), observations: observations)
        await store.refresh()
        store.selection = [try XCTUnwrap(store.files.first?.id)]
        let source = try dictionarySource("cats a")
        store.beginImport()
        await store.finishImport(.success([source]))?.value
        let first = try XCTUnwrap(store.pendingDictionaryImport)
        try Data("dogs a".utf8).write(to: source)
        await store.confirmDictionaryImport(first)
        let current = try XCTUnwrap(store.pendingDictionaryImport)
        XCTAssertNotEqual(first.id, current.id)
        store.cancelDictionaryImport(first)
        await store.confirmDictionaryImport(first)
        XCTAssertEqual(store.pendingDictionaryImport?.id, current.id)
        XCTAssertEqual(store.pendingDictionaryImport?.sourceText, "dogs a")
        XCTAssertNil(store.pendingChange)
        XCTAssertNil(store.notice)
        XCTAssertEqual(observations.writeCount, 0)
        store.cancelDictionaryImport(current)
        XCTAssertNil(store.pendingDictionaryImport)
        await store.shutdown()
    }

    func testCompletedDictionaryConsentCannotDismissTheReplaceWarning() async throws {
        let observations = SimulatedObservations()
        let store = makeStore(SimulatedConfiguration(appletID: NeoApplet.dictionary), observations: observations)
        await store.refresh()
        store.selection = [try XCTUnwrap(store.files.first?.id)]
        store.beginImport()
        await store.finishImport(.success([try dictionarySource("cats a")]))?.value
        let warning = try XCTUnwrap(store.pendingDictionaryImport)
        await store.confirmDictionaryImport(warning)
        let replacement = try XCTUnwrap(store.pendingChange)
        store.cancelDictionaryImport(warning)
        await store.confirmDictionaryImport(warning)
        XCTAssertEqual(store.pendingChange?.id, replacement.id)
        XCTAssertNil(store.pendingDictionaryImport)
        XCTAssertNil(store.notice)
        XCTAssertEqual(observations.writeCount, 0)
        await store.confirm(replacement, saveRecovery: false)
        XCTAssertEqual(observations.writeCount, 1)
        await store.shutdown()
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
