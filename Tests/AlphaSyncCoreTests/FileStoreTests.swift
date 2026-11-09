#if os(macOS)
import Foundation
import Darwin
import XCTest
@testable import AlphaSyncCore

final class FileStoreTests: XCTestCase {
    func testImportsRejectSpecialFilesWithoutWaiting() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let pipe = root.appendingPathComponent("Pipe.txt")
        XCTAssertEqual(mkfifo(pipe.path, 0o600), 0)
        XCTAssertThrowsError(try TextFiles.read(pipe))
        XCTAssertThrowsError(try TextFiles.read(root))
        let file = root.appendingPathComponent("Text.txt")
        try Data("Regular file".utf8).write(to: file)
        let link = root.appendingPathComponent("Link.txt")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        XCTAssertEqual(try TextFiles.read(link), "Regular file")
    }

    func testEmptyPasswordAttributesCannotBeSentToNeo() throws {
        var raw = try NeoFileAttributes(name: "File 1").raw
        raw.replaceSubrange(16..<24, with: Data(repeating: 0, count: 8))
        let malformed = try NeoFileAttributes(raw: raw)
        XCTAssertThrowsError(try malformed.validateForWriting())
        XCTAssertNoThrow(try NeoFileAttributes(name: "File 1").validateForWriting())
    }

    func testConcurrentExportsPreserveExistingFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let original = Data("Keep the original".utf8), output = Data(repeating: 65, count: 65536)
        try original.write(to: root.appendingPathComponent("Notes.txt"))
        DispatchQueue.concurrentPerform(iterations: 12) { _ in
            do { try AtomicFileStore.write(output, name: "Notes", extension: "txt", to: root) }
            catch { XCTFail(error.localizedDescription) }
        }
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Notes.txt")), original)
        let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        XCTAssertEqual(files.count, 13)
        for file in files where file.lastPathComponent != "Notes.txt" {
            XCTAssertEqual(try Data(contentsOf: file), output)
            let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
            XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        }
    }
    func testIncompleteFoldersNeverReplaceCompletedBackups() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try AtomicFileStore.createFolder(in: root, name: "2026-11-09", incomplete: true)
        try AtomicFileStore.write(Data("first".utf8), name: "File 1", extension: "txt", to: first)
        let complete = try AtomicFileStore.completeFolder(first)
        let second = try AtomicFileStore.createFolder(in: root, name: "2026-11-09", incomplete: true)
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(try Data(contentsOf: complete.appendingPathComponent("File 1.txt")), Data("first".utf8))
        XCTAssertTrue(second.lastPathComponent.hasSuffix(" (Incomplete)"))
    }
    func testExportsDoNotFollowDirectorySymlinks() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let link = root.appendingPathComponent("Linked")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: root)
        XCTAssertThrowsError(try AtomicFileStore.write(Data([1]), name: "Unsafe", extension: "txt", to: link))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Unsafe.txt").path))
        XCTAssertFalse(AtomicFileStore.safeComponent("../a/b:c").contains("/"))
    }
}
#endif
