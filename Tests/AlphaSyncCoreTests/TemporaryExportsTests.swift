#if os(macOS)
import Foundation
import XCTest
@testable import AlphaSyncCore

final class TemporaryExportsTests: XCTestCase {
    private func root() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        return folder
    }

    func testCleanupRemovesOnlyExpiredInactiveSessions() async throws {
        let parent = try root()
        let now = Date()
        let old = now.addingTimeInterval(-8 * 86400)
        var expired: TemporaryExports? = TemporaryExports(root: parent)
        let expiredFile = try await expired!.createFolder(now: old)
        try Data("Old temporary text".utf8).write(to: expiredFile.appendingPathComponent("Note.txt"))
        expired = nil

        let active = TemporaryExports(root: parent)
        let activeFolder = try await active.createFolder(now: old)
        var recent: TemporaryExports? = TemporaryExports(root: parent)
        let recentFolder = try await recent!.createFolder(now: now.addingTimeInterval(-3600))
        recent = nil
        let unrelated = parent.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: unrelated, withIntermediateDirectories: false)
        let link = parent.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: unrelated)

        let current = TemporaryExports(root: parent)
        let currentFolder = try await current.createFolder(now: now)
        XCTAssertFalse(FileManager.default.fileExists(atPath: expiredFile.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: activeFolder.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: recentFolder.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelated.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: link.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: currentFolder.path))
        // Keep the old session active until after the cleanup assertions.
        await active.retain(activeFolder)
    }

    func testFailedExportsAreDiscardedButPromisedFilesRemain() async throws {
        let staging = TemporaryExports(root: try root())
        let failed = try await staging.createFolder()
        try Data([1]).write(to: failed.appendingPathComponent("Partial.txt"))
        await staging.discard(failed)
        XCTAssertFalse(FileManager.default.fileExists(atPath: failed.path))
        let promised = try await staging.createFolder()
        let file = try AtomicFileStore.write(Data("Keep for the receiver".utf8), name: "Note", extension: "txt", to: promised)
        await staging.retain(promised)
        await staging.discard(promised)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        let attributes = try FileManager.default.attributesOfItem(atPath: promised.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o700)
        let unrelated = try root()
        await staging.discard(unrelated)
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelated.path))
    }

    func testStagingRejectsARootSymlink() async throws {
        let parent = try root()
        let target = try root()
        let link = parent.appendingPathComponent("Linked exports")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        let staging = TemporaryExports(root: link)
        do {
            _ = try await staging.createFolder()
            XCTFail("A symlink was used as the staging root")
        } catch {
            XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: target.path).isEmpty)
        }
    }
}
#endif
