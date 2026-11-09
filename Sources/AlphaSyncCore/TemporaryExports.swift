#if os(macOS)
import Foundation
import Darwin

/// Keep promised files alive for the receiver. Clean only recognised, inactive old sessions.
public actor TemporaryExports {
    private let root: URL
    private var session: URL?
    private var sessionLock: Int32 = -1
    private var pending = Set<URL>()
    private static let lifetime: TimeInterval = 7 * 86400

    public init(root: URL = FileManager.default.temporaryDirectory.appendingPathComponent("AlphaSync Drag Exports", isDirectory: true)) {
        self.root = root
    }

    deinit { if sessionLock >= 0 { close(sessionLock) } }

    public func createFolder(now: Date = Date()) throws -> URL {
        let parent = try sessionFolder(now: now)
        let folder = try AtomicFileStore.createFolder(in: parent, name: UUID().uuidString)
        pending.insert(folder)
        return folder
    }

    public func retain(_ folder: URL) { pending.remove(folder) }

    public func discard(_ folder: URL) {
        guard pending.remove(folder) != nil else { return }
        try? FileManager.default.removeItem(at: folder)
    }

    private func sessionFolder(now: Date) throws -> URL {
        if let session { return session }
        let manager = FileManager.default
        try manager.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let attributes = try manager.attributesOfItem(atPath: root.path)
        guard attributes[.type] as? FileAttributeType == .typeDirectory,
              (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == geteuid(),
              let permissions = attributes[.posixPermissions] as? NSNumber, permissions.intValue & 0o077 == 0 else {
            throw NeoError.device("The temporary export folder is not a private folder owned by this account.")
        }
        try removeExpiredSessions(now: now)
        let folder = try AtomicFileStore.createFolder(in: root, name: UUID().uuidString)
        let descriptor = open(folder.appendingPathComponent(".session-lock").path,
                              O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        var keep = false
        defer {
            if !keep {
                if descriptor >= 0 { close(descriptor) }
                try? manager.removeItem(at: folder)
            }
        }
        guard descriptor >= 0, flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        let marker: [String: Any] = ["kind": "AlphaSyncDragExports", "formatVersion": 1, "createdAt": now,
                                     "session": folder.lastPathComponent]
        let bytes = try PropertyListSerialization.data(fromPropertyList: marker, format: .xml, options: 0)
        try AtomicFileStore.write(bytes, name: ".session", extension: "plist", to: folder)
        session = folder
        sessionLock = descriptor
        keep = true
        return folder
    }

    private func removeExpiredSessions(now: Date) throws {
        let manager = FileManager.default
        for folder in try manager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) {
            guard UUID(uuidString: folder.lastPathComponent) != nil,
                  let attributes = try? manager.attributesOfItem(atPath: folder.path),
                  attributes[.type] as? FileAttributeType == .typeDirectory,
                  (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == geteuid() else { continue }
            let descriptor = open(folder.appendingPathComponent(".session-lock").path, O_RDWR | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
            guard descriptor >= 0 else { continue }
            defer { close(descriptor) }
            var info = stat()
            guard fstat(descriptor, &info) == 0, info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
                  info.st_uid == geteuid(), flock(descriptor, LOCK_EX | LOCK_NB) == 0,
                  let bytes = try? AtomicFileStore.readRegularFile(folder.appendingPathComponent(".session.plist"), maximum: 4096),
                  let marker = try? PropertyListSerialization.propertyList(from: bytes, format: nil) as? [String: Any],
                  marker["kind"] as? String == "AlphaSyncDragExports", marker["formatVersion"] as? Int == 1,
                  marker["session"] as? String == folder.lastPathComponent,
                  let created = marker["createdAt"] as? Date, now.timeIntervalSince(created) > Self.lifetime else { continue }
            try manager.removeItem(at: folder)
        }
    }
}
#endif
