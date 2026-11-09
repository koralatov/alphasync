#if os(macOS)
import Foundation
import Darwin

public enum AtomicFileStore {
    public static let incompleteSuffix = " (Incomplete)"

    public static func safeComponent(_ value: String) -> String {
        var result = String(value.unicodeScalars.map { scalar -> Character in
            if CharacterSet.controlCharacters.contains(scalar) || "/:\\".unicodeScalars.contains(scalar) { return "-" }
            return Character(String(scalar))
        }).trimmingCharacters(in: .whitespacesAndNewlines)
        while result.utf8.count > 180 { result.removeLast() }
        return result.isEmpty || result == "." || result == ".." ? "Untitled" : result
    }

    public static func createFolder(in parent: URL, name: String, incomplete: Bool = false) throws -> URL {
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let component = safeComponent(name)
        for number in 0..<10000 {
            let candidate = parent.appendingPathComponent(component + (number == 0 ? "" : " (\(number))") + (incomplete ? incompleteSuffix : ""), isDirectory: true)
            if incomplete {
                let complete = parent.appendingPathComponent(component + (number == 0 ? "" : " (\(number))"))
                var existing = stat()
                if lstat(complete.path, &existing) == 0 { continue }
                if errno != ENOENT { throw posixError() }
            }
            if mkdir(candidate.path, 0o700) == 0 { return candidate }
            if errno != EEXIST { throw posixError() }
        }
        throw NeoError.device("Too many folders already use this name. Choose another backup folder.")
    }

    @discardableResult
    public static func write(_ data: Data, name: String, extension suffix: String, to folder: URL) throws -> URL {
        try publish(data, name: name, extension: suffix, folder: folder, replacingOwnLog: false)
    }

    /// Only this backup session’s known log is replaced. Exported and recovery files are never replaced.
    public static func updateBackupLog(_ data: Data, in folder: URL) throws {
        _ = try publish(data, name: "AlphaSync Backup Log", extension: "plist", folder: folder, replacingOwnLog: true)
    }

    private static func publish(_ data: Data, name: String, extension suffix: String, folder: URL, replacingOwnLog: Bool) throws -> URL {
        let directory = open(folder.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard directory >= 0 else { throw posixError() }
        defer { close(directory) }
        let temporary = ".alphasync-\(UUID().uuidString).tmp"
        let descriptor = openat(directory, temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw posixError() }
        var opened = true
        defer {
            if opened { close(descriptor) }
            unlinkat(directory, temporary, 0)
        }
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                guard let address = bytes.baseAddress else { throw NeoError.device("The export buffer is unavailable.") }
                let count = Darwin.write(descriptor, address.advanced(by: offset), bytes.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw posixError() }
                offset += count
            }
        }
        guard fsync(descriptor) == 0 else { throw posixError() }
        let closed = close(descriptor); opened = false
        guard closed == 0 else { throw posixError() }
        let base = safeComponent(name), ext = safeComponent(suffix)
        for number in 0..<10000 {
            let filename = base + (number == 0 ? "" : " (\(number))") + "." + ext
            let flags: UInt32 = replacingOwnLog ? 0 : UInt32(RENAME_EXCL)
            if renameatx_np(directory, temporary, directory, filename, flags) == 0 {
                return folder.appendingPathComponent(filename)
            }
            if replacingOwnLog || errno != EEXIST { throw posixError() }
        }
        throw NeoError.device("Too many files already use this name. Choose another destination.")
    }

    public static func completeFolder(_ pending: URL) throws -> URL {
        guard pending.lastPathComponent.hasSuffix(incompleteSuffix) else { throw NeoError.device("This is not an incomplete AlphaSync folder.") }
        let attributes = try FileManager.default.attributesOfItem(atPath: pending.path)
        guard attributes[.type] as? FileAttributeType == .typeDirectory else { throw NeoError.device("The backup folder was replaced or moved.") }
        let name = String(pending.lastPathComponent.dropLast(incompleteSuffix.count))
        let complete = pending.deletingLastPathComponent().appendingPathComponent(name, isDirectory: true)
        guard renameatx_np(AT_FDCWD, pending.path, AT_FDCWD, complete.path, UInt32(RENAME_EXCL)) == 0 else { throw posixError() }
        return complete
    }

    public static func expireRecoveryCopies(in root: URL, olderThan days: Int, now: Date = Date()) throws {
        guard [7, 30, 90].contains(days) else { return }
        for url in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) {
            if url.lastPathComponent.hasSuffix(incompleteSuffix) { continue }
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard attributes[.type] as? FileAttributeType == .typeDirectory else { continue }
            let metadata = url.appendingPathComponent(".recovery-information.plist")
            guard let bytes = try? readRegularFile(metadata, maximum: 65536),
                  let record = try? PropertyListSerialization.propertyList(from: bytes, format: nil) as? [String: Any],
                  record["kind"] as? String == "AlphaSyncRecoveryCopy",
                  let version = record["formatVersion"] as? Int, [1, 2].contains(version),
                  let created = record["createdAt"] as? Date,
                  now.timeIntervalSince(created) > Double(days) * 86400 else { continue }
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        }
    }

    private static func readRegularFile(_ url: URL, maximum: Int) throws -> Data {
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { throw posixError() }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var attributes = stat()
        guard fstat(descriptor, &attributes) == 0, attributes.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              attributes.st_size <= Int64(maximum) else { throw NeoError.device("Recovery metadata is not a small regular file.") }
        let bytes = try handle.read(upToCount: maximum + 1) ?? Data()
        guard bytes.count <= maximum else { throw NeoError.device("Recovery metadata is too large.") }
        return bytes
    }
    private static func posixError() -> NSError { NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
}
#endif
