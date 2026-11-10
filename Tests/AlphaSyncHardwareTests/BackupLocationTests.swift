import Foundation
import XCTest
import ServiceManagement
@testable import AlphaSyncUI

@MainActor
final class BackupLocationTests: XCTestCase {
    private func defaults() -> UserDefaults {
        let name = "AlphaSync-LocationTests-" + UUID().uuidString
        addTeardownBlock { UserDefaults(suiteName: name)?.removePersistentDomain(forName: name) }
        return UserDefaults(suiteName: name)!
    }
    private func root() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func preferences(defaults: UserDefaults, initial: URL) -> Preferences {
        Preferences(defaults: defaults, loginItem: SMAppService.loginItem(identifier: "com.tsoniq.AlphaSyncLauncher"),
                    initialBackupFolder: initial)
    }

    func testDefaultDestinationIsBookmarkedBeforeItsFirstUseAndFollowsAMove() throws {
        let root = try root(), defaults = defaults()
        let original = root.appendingPathComponent("First backups", isDirectory: true)
        let preferences = preferences(defaults: defaults, initial: original)
        XCTAssertFalse(FileManager.default.fileExists(atPath: original.path))
        _ = try preferences.resolvedBackupFolder()
        XCTAssertFalse(FileManager.default.fileExists(atPath: original.path))
        _ = try preferences.prepareBackupFolder()
        XCTAssertNotNil(defaults.data(forKey: "BackupFolderBookmark"))
        let moved = root.appendingPathComponent("Moved first backups", isDirectory: true)
        try FileManager.default.moveItem(at: original, to: moved)
        let relaunched = self.preferences(defaults: defaults, initial: original)
        XCTAssertEqual(try relaunched.prepareBackupFolder(), moved.resolvingSymlinksInPath())
        XCTAssertFalse(FileManager.default.fileExists(atPath: original.path))
    }

    func testRemovingTheFirstDefaultDestinationDoesNotRecreateIt() throws {
        let initial = try root().appendingPathComponent("First backups", isDirectory: true)
        let preferences = preferences(defaults: defaults(), initial: initial)
        _ = try preferences.prepareBackupFolder()
        try FileManager.default.removeItem(at: initial)
        XCTAssertThrowsError(try preferences.prepareBackupFolder())
        XCTAssertFalse(FileManager.default.fileExists(atPath: initial.path))
    }

    func testChosenBackupFolderFollowsMovesAndSurvivesRelaunch() throws {
        let root = try root(), defaults = defaults()
        let original = root.appendingPathComponent("Backups", isDirectory: true)
        try FileManager.default.createDirectory(at: original, withIntermediateDirectories: false)
        let preferences = Preferences(defaults: defaults)
        try preferences.selectBackupFolder(original)
        let moved = root.appendingPathComponent("Renamed backups", isDirectory: true)
        try FileManager.default.moveItem(at: original, to: moved)
        XCTAssertEqual(try preferences.resolvedBackupFolder(), moved.resolvingSymlinksInPath())
        let relaunched = Preferences(defaults: defaults)
        XCTAssertEqual(try relaunched.resolvedBackupFolder(), moved.resolvingSymlinksInPath())
        XCTAssertFalse(FileManager.default.fileExists(atPath: original.path))
    }

    func testDeletedFolderDoesNotRecreateItsOldPath() throws {
        let preferences = Preferences(defaults: defaults())
        let folder = try root().appendingPathComponent("Selected backups", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        try preferences.selectBackupFolder(folder)
        try FileManager.default.removeItem(at: folder)
        XCTAssertThrowsError(try preferences.resolvedBackupFolder())
        XCTAssertNotNil(preferences.backupLocationIssue)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
    }

    func testInvalidBookmarkDoesNotSilentlyFallBackToItsSavedPath() throws {
        let defaults = defaults(), folder = try root()
        defaults.set(folder.path, forKey: "BackupFolder")
        defaults.set(Data([0, 1, 2]), forKey: "BackupFolderBookmark")
        let preferences = Preferences(defaults: defaults)
        XCTAssertThrowsError(try preferences.resolvedBackupFolder())
        try preferences.selectBackupFolder(folder)
        XCTAssertEqual(try preferences.resolvedBackupFolder(), folder.resolvingSymlinksInPath())
        XCTAssertNil(preferences.backupLocationIssue)
    }

    func testExistingLegacyPathIsMigratedToABookmark() throws {
        let defaults = defaults(), folder = try root()
        defaults.set(folder.path, forKey: "BackupFolder")
        let preferences = Preferences(defaults: defaults)
        XCTAssertEqual(try preferences.resolvedBackupFolder(), folder.resolvingSymlinksInPath())
        XCTAssertNotNil(defaults.data(forKey: "BackupFolderBookmark"))
    }

    func testMissingCustomLegacyPathRequiresChoosingAFolder() throws {
        let defaults = defaults(), folder = try root().appendingPathComponent("Missing", isDirectory: true)
        defaults.set(folder.path, forKey: "BackupFolder")
        let preferences = Preferences(defaults: defaults)
        XCTAssertThrowsError(try preferences.resolvedBackupFolder())
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
    }
}
