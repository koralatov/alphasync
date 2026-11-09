import Foundation
import AlphaSyncCore

public struct RecoveryOptions: Sendable {
    public let enabled: Bool
    public let folder: URL
    public let retentionDays: Int
    public init(enabled: Bool, folder: URL, retentionDays: Int) {
        self.enabled = enabled; self.folder = folder; self.retentionDays = retentionDays
    }
}

public struct PreparedChange: Identifiable, Sendable {
    public struct Item: Sendable {
        public let file: NeoFile
        public let original: Data
        public let replacement: Data
    }
    public let id = UUID()
    public let connection: UUID
    public let applet: NeoApplet
    public let items: [Item]
    public let sourceName: String?
    public let title: String
    public let action: String
    public let explanation: String
}

public struct ChangeResult: Sendable {
    public let snapshot: NeoSnapshot
    public let recoveryFolder: URL?
}

public final class StopRequest: @unchecked Sendable {
    private let lock = NSLock()
    private var requested = false
    public init() {}
    public func stop() { lock.lock(); requested = true; lock.unlock() }
    public var isRequested: Bool { lock.lock(); defer { lock.unlock() }; return requested }
}

public struct BackupResult: Sendable {
    public let saved: Int
    public let expected: Int
    public let folders: [URL]
    public let stopped: Bool
    public let failures: [String]
    public var complete: Bool { !stopped && failures.isEmpty && saved == expected }
}

extension DeviceService {
    public func prepareReplacement(file: NeoFileID, from source: URL) async throws -> PreparedChange {
        try await perform { access in
            let snapshot = try access.snapshot(for: file.connection)
            guard let applet = snapshot.applets.first(where: { $0.id == file.applet }),
                  let node = applet.files.first(where: { $0.id == file }) else { throw NeoError.disconnected }
            let engine = try access.engine(for: file.connection)
            let limits = try engine.fileLimits(applet: file.applet)
            let replacement = try FileCodec.converted(TextFiles.read(source), applet: file.applet, limits: limits)
            let memory = try engine.availableMemory(), attributes = try engine.attributes(applet: file.applet, index: file.index)
            try limits.validate(replacement.count, allocation: attributes.allocation, available: memory.ram)
            let original = try engine.readFile(applet: file.applet, index: file.index)
            return PreparedChange(connection: file.connection, applet: applet,
                                  items: [.init(file: node, original: original, replacement: replacement)], sourceName: source.lastPathComponent,
                                  title: "Replace ‘\(node.displayName)’?", action: "Replace",
                                  explanation: "The text on your Neo will be replaced with ‘\(source.lastPathComponent)’. This cannot be undone.")
        }
    }

    public func prepareClear(connection: UUID, appletID: UInt16, files selected: Set<NeoFileID>?) async throws -> PreparedChange {
        try await perform { access in
            let snapshot = try access.update(connection)
            guard let applet = snapshot.applets.first(where: { $0.id == appletID }), applet.canWrite else {
                throw NeoError.device("This applet’s files cannot be cleared by AlphaSync.")
            }
            let files = applet.files.filter { selected?.contains($0.id) ?? true }
            guard !files.isEmpty, selected == nil || Set(files.map(\.id)) == selected else { throw NeoError.disconnected }
            let engine = try access.engine(for: connection), limits = try engine.fileLimits(applet: appletID)
            let empty = try FileCodec.converted("", applet: appletID, limits: limits)
            let items = try files.map { file in
                PreparedChange.Item(file: file, original: try engine.readFile(applet: appletID, index: file.id.index), replacement: empty)
            }
            let all = selected == nil
            let title = all ? "Clear all files in ‘\(applet.name)’?" : (files.count == 1 ? "Clear ‘\(files[0].displayName)’?" : "Clear \(files.count.formatted()) selected files?")
            return PreparedChange(connection: connection, applet: applet, items: items, sourceName: nil,
                                  title: title, action: all ? "Clear All Files" : (files.count == 1 ? "Clear File" : "Clear Selected Files"),
                                  explanation: "The named contents on your Neo will be cleared. This cannot be undone.")
        }
    }

    public func apply(_ change: PreparedChange, recovery: RecoveryOptions) async throws -> ChangeResult {
        try await perform { access in
            var completed = 0
            var folder: URL?
            do {
                let engine = try access.engine(for: change.connection)
                let latest = try access.update(change.connection)
                guard let applet = latest.applets.first(where: { $0.id == change.applet.id }) else { throw NeoError.disconnected }
                guard change.items.allSatisfy({ item in applet.files.contains(where: { $0.id == item.file.id }) }) else { throw NeoError.disconnected }
                // Recheck every original before saving recovery or beginning a multi-file clear.
                for item in change.items {
                    guard try engine.readFile(applet: applet.id, index: item.file.id.index) == item.original else {
                        throw NeoError.device("A file changed after the warning opened.  Review the current files and try again.")
                    }
                }
                folder = recovery.enabled ? try Self.saveRecovery(change, options: recovery) : nil
                for item in change.items {
                    try engine.writeFile(item.replacement, applet: applet.id, index: item.file.id.index, expectedOriginal: item.original)
                    completed += 1
                }
                return ChangeResult(snapshot: try access.update(change.connection), recoveryFolder: folder)
            } catch {
                throw OperationFailure(error, action: .change, completedFiles: completed, recoveryFolder: folder)
            }
        }
    }

    public func create(connection: UUID, appletID: UInt16, from source: URL) async throws -> NeoSnapshot {
        try await perform { access in
            var completed = 0
            do {
                let engine = try access.engine(for: connection)
                let limits = try engine.fileLimits(applet: appletID)
                let converted = try FileCodec.converted(TextFiles.read(source), applet: appletID, limits: limits)
                _ = try engine.createFile(converted, name: source.deletingPathExtension().lastPathComponent, applet: appletID)
                completed = 1
                return try access.update(connection)
            } catch {
                throw OperationFailure(error, action: .add, completedFiles: completed)
            }
        }
    }

    public func rename(_ file: NeoFileID, to name: String) async throws -> NeoSnapshot {
        try await perform { access in
            var completed = 0
            do {
                try access.engine(for: file.connection).rename(applet: file.applet, index: file.index, to: name)
                completed = 1
                return try access.update(file.connection)
            } catch {
                throw OperationFailure(error, action: .rename, completedFiles: completed)
            }
        }
    }

    public func export(_ files: [NeoFileID], to destination: URL) async throws -> [URL] {
        try await perform { access in
            try files.map { id in
                let snapshot = try access.snapshot(for: id.connection)
                guard let applet = snapshot.applets.first(where: { $0.id == id.applet }),
                      let file = applet.files.first(where: { $0.id == id }) else { throw NeoError.disconnected }
                let raw = try access.engine(for: id.connection).readFile(applet: id.applet, index: id.index)
                let text = try FileCodec.text(raw, applet: applet)
                return try AtomicFileStore.write(TextFiles.utf8(text), name: file.displayName,
                                                  extension: FileCodec.fileExtension(applet: id.applet), to: destination)
            }
        }
    }

    private static func saveRecovery(_ change: PreparedChange, options: RecoveryOptions) throws -> URL {
        let root = options.folder.appendingPathComponent("Recovery Copies", isDirectory: true)
        let now = Date(), formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let pending = try AtomicFileStore.createFolder(in: root, name: formatter.string(from: now) + " " + String(UUID().uuidString.prefix(8)), incomplete: true)
        var records: [[String: Any]] = []
        for item in change.items {
            let text = try FileCodec.text(item.original, applet: change.applet)
            let readable = try AtomicFileStore.write(TextFiles.utf8(text), name: item.file.displayName,
                                                    extension: FileCodec.fileExtension(applet: change.applet.id), to: pending)
            let raw = try AtomicFileStore.write(item.original, name: item.file.displayName, extension: "neo", to: pending)
            records.append(["name": item.file.displayName, "applet": Int(change.applet.id), "index": Int(item.file.id.index),
                            "text": readable.lastPathComponent, "raw": raw.lastPathComponent])
        }
        let record: [String: Any] = ["kind": "AlphaSyncRecoveryCopy", "formatVersion": 2, "createdAt": now, "files": records]
        let metadata = try PropertyListSerialization.data(fromPropertyList: record, format: .xml, options: 0)
        try AtomicFileStore.write(metadata, name: ".recovery-information", extension: "plist", to: pending)
        let complete = try AtomicFileStore.completeFolder(pending)
        do { try AtomicFileStore.expireRecoveryCopies(in: root, olderThan: options.retentionDays, now: now) }
        catch {
            let reason = NeoError.device("Older recovery copies could not be moved to Trash.  \(error.localizedDescription)")
            throw OperationFailure(reason, action: .change, recoveryFolder: complete)
        }
        return complete
    }
}
