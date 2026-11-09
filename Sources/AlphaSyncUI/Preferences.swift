import Foundation
import Combine
import ServiceManagement

@MainActor
protocol LoginItemManaging: AnyObject {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
}

extension SMAppService: LoginItemManaging {}

public enum FileFilter: Int, CaseIterable, Identifiable, Sendable {
    case alphaWord = 0, textApplets = 1, allApplets = 2
    public var id: Int { rawValue }
    public var title: String {
        switch self {
        case .alphaWord: return "AlphaWord files"
        case .textApplets: return "AlphaWord and dictionary files"
        case .allApplets: return "All applet files"
        }
    }
    public var appletIDs: Set<UInt16>? {
        switch self {
        case .alphaWord: return [0xa000]
        case .textApplets: return [0xa000, 0xa005]
        case .allApplets: return nil
        }
    }
}

@MainActor
public final class Preferences: ObservableObject {
    @Published public var filter: FileFilter { didSet { defaults.set(filter.rawValue, forKey: "FilterMode") } }
    @Published public private(set) var backupFolder: URL
    @Published public private(set) var backupLocationIssue: String?
    @Published public var saveBackupLogs: Bool { didSet { defaults.set(saveBackupLogs, forKey: "SaveBackupLogs") } }
    @Published public var saveRecoveryCopies: Bool { didSet { defaults.set(saveRecoveryCopies, forKey: "SaveRecoveryCopies") } }
    @Published public var retentionDays: Int { didSet { defaults.set(retentionDays, forKey: "RecoveryRetentionDays") } }
    @Published public var automaticOpening: Bool
    @Published public private(set) var loginStatus = ""
    private let defaults: UserDefaults
    private let loginItem: any LoginItemManaging

    public convenience init(defaults: UserDefaults = .standard) {
        self.init(defaults: defaults, loginItem: SMAppService.loginItem(identifier: "com.tsoniq.AlphaSyncLauncher"))
    }

    init(defaults: UserDefaults, loginItem: any LoginItemManaging) {
        self.defaults = defaults
        self.loginItem = loginItem
        defaults.register(defaults: ["FilterMode": 1, "BackupFolder": ("~/Documents/AlphaSync" as NSString).expandingTildeInPath,
                                     "SaveBackupLogs": false, "SaveRecoveryCopies": true, "RecoveryRetentionDays": 30, "AutoRun": false])
        filter = FileFilter(rawValue: defaults.integer(forKey: "FilterMode")) ?? .textApplets
        let path = defaults.string(forKey: "BackupFolder") ?? ("~/Documents/AlphaSync" as NSString).expandingTildeInPath
        backupFolder = URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
        saveBackupLogs = defaults.bool(forKey: "SaveBackupLogs"); saveRecoveryCopies = defaults.bool(forKey: "SaveRecoveryCopies")
        let days = defaults.integer(forKey: "RecoveryRetentionDays")
        retentionDays = [0, 7, 30, 90].contains(days) ? days : 30
        automaticOpening = defaults.bool(forKey: "AutoRun")
        refreshLoginStatus()
    }
    public func selectBackupFolder(_ chosen: URL) throws {
        let folder = chosen.resolvingSymlinksInPath()
        guard try folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }
        let bookmark = try folder.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        defaults.set(bookmark, forKey: "BackupFolderBookmark")
        defaults.set(folder.path, forKey: "BackupFolder")
        backupFolder = folder
        backupLocationIssue = nil
    }

    /// A failed saved bookmark never falls back to creating its old path.
    public func resolvedBackupFolder() throws -> URL {
        do {
            if let bookmark = defaults.data(forKey: "BackupFolderBookmark") {
                var stale = false
                let folder = try URL(resolvingBookmarkData: bookmark, options: [.withoutUI, .withoutMounting],
                                     relativeTo: nil, bookmarkDataIsStale: &stale).resolvingSymlinksInPath()
                guard try folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else { throw CocoaError(.fileNoSuchFile) }
                if stale {
                    defaults.set(try folder.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil), forKey: "BackupFolderBookmark")
                }
                defaults.set(folder.path, forKey: "BackupFolder")
                backupFolder = folder
            } else {
                var directory: ObjCBool = false
                if FileManager.default.fileExists(atPath: backupFolder.path, isDirectory: &directory) {
                    guard directory.boolValue else { throw CocoaError(.fileNoSuchFile) }
                    try selectBackupFolder(backupFolder)
                } else {
                    let initial = URL(fileURLWithPath: ("~/Documents/AlphaSync" as NSString).expandingTildeInPath, isDirectory: true)
                    guard backupFolder.standardizedFileURL == initial.standardizedFileURL else { throw CocoaError(.fileNoSuchFile) }
                }
            }
            backupLocationIssue = nil
            return backupFolder
        } catch {
            let message = "The saved backup folder is unavailable. Connect its drive or choose the folder again in Settings.\n\n\(backupFolder.path)\n\n\(error.localizedDescription)"
            backupLocationIssue = message
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoSuchFileError,
                          userInfo: [NSLocalizedDescriptionKey: message, NSUnderlyingErrorKey: error])
        }
    }
    public func refreshLoginStatus() {
        switch loginItem.status {
        case .enabled: loginStatus = "Automatic opening is enabled."
        case .requiresApproval: loginStatus = "Approve AlphaSync in Login Items to finish enabling automatic opening."
        case .notRegistered: loginStatus = "Automatic opening is off."
        case .notFound: loginStatus = "The bundled launch helper could not be found. Keep AlphaSync in Applications."
        @unknown default: loginStatus = "The system could not report the login-item state."
        }
    }
    public func setAutomaticOpening(_ enabled: Bool) {
        let previous = automaticOpening
        automaticOpening = enabled
        defaults.set(enabled, forKey: "AutoRun")
        do {
            if enabled {
                if loginItem.status != .enabled && loginItem.status != .requiresApproval { try loginItem.register() }
            } else { try loginItem.unregister() }
            refreshLoginStatus()
        } catch {
            if enabled && loginItem.status == .requiresApproval {
                refreshLoginStatus()
                return
            }
            automaticOpening = previous
            defaults.set(previous, forKey: "AutoRun")
            loginStatus = "Automatic opening could not be changed. \(error.localizedDescription)"
        }
    }
    public func openLoginSettings() { SMAppService.openSystemSettingsLoginItems() }
}
