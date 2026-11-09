import Foundation
import Combine
import ServiceManagement

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
    @Published public var backupFolder: URL { didSet { defaults.set(backupFolder.path, forKey: "BackupFolder") } }
    @Published public var saveBackupLogs: Bool { didSet { defaults.set(saveBackupLogs, forKey: "SaveBackupLogs") } }
    @Published public var saveRecoveryCopies: Bool { didSet { defaults.set(saveRecoveryCopies, forKey: "SaveRecoveryCopies") } }
    @Published public var retentionDays: Int { didSet { defaults.set(retentionDays, forKey: "RecoveryRetentionDays") } }
    @Published public var automaticOpening: Bool
    @Published public private(set) var loginStatus = ""
    private let defaults: UserDefaults
    private let loginItem = SMAppService.loginItem(identifier: "com.tsoniq.AlphaSyncLauncher")

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
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
        do {
            if enabled { try loginItem.register() } else { try loginItem.unregister() }
            automaticOpening = enabled; defaults.set(enabled, forKey: "AutoRun")
            refreshLoginStatus()
        } catch {
            loginStatus = "Automatic opening could not be changed. \(error.localizedDescription)"
        }
    }
    public func openLoginSettings() { SMAppService.openSystemSettingsLoginItems() }
}
