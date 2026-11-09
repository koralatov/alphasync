import Foundation
import Combine
import AlphaSyncCore
import AlphaSyncHardware

public struct AppNotice: Identifiable {
    public let id = UUID()
    public let title: String
    public let message: String
    public init(_ title: String, _ message: String) { self.title = title; self.message = message }
}

public struct ReaderRequest: Codable, Hashable, Sendable {
    public let id: UUID
    public let file: NeoFileID
    public let name: String
    public init(file: NeoFile) { id = UUID(); self.file = file.id; name = file.displayName }
}

public enum SidebarSelection: Hashable {
    case device(UUID)
    case applet(UUID, UInt16)
    public var connection: UUID {
        switch self { case .device(let id), .applet(let id, _): return id }
    }
}

@MainActor
public final class AppStore: ObservableObject {
    @Published public var devices: [NeoSnapshot] = []
    @Published public var sidebar: SidebarSelection?
    @Published public var selection = Set<NeoFileID>()
    @Published public var notice: AppNotice?
    @Published public var pendingChange: PreparedChange?
    @Published public var backupResult: BackupResult?
    @Published public var operationText = ""
    @Published public var progress: Double?
    @Published public var connectionIssue: String?
    @Published public var showImporter = false
    @Published public var showExportFolder = false
    @Published public var showInspector = false
    @Published public private(set) var shuttingDown = false
    @Published private var activities = 0
    public let preferences: Preferences
    public let service: DeviceService
    public let temporaryExports = FileManager.default.temporaryDirectory.appendingPathComponent("AlphaSync-Exports-" + UUID().uuidString, isDirectory: true)
    public var busy: Bool { activities > 0 || shuttingDown || pendingChange != nil }
    public var connected: Bool { !devices.isEmpty }
    public var chosenDevice: NeoSnapshot? { devices.first { $0.connection == sidebar?.connection } ?? devices.first }
    public var chosenApplet: NeoApplet? {
        guard case .applet(_, let id) = sidebar else { return nil }
        return chosenDevice?.applets.first { $0.id == id }
    }
    public var files: [NeoFile] {
        let applets = chosenApplet.map { [$0] } ?? chosenDevice?.applets ?? []
        return applets.filter { preferences.filter.appletIDs?.contains($0.id) ?? true }.flatMap(\.files).sorted {
            $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
    }
    public var selectedFiles: [NeoFile] { files.filter { selection.contains($0.id) } }
    public var clearTitle: String {
        if selection.count == 1 { return "Clear File…" }
        return selection.isEmpty ? "Clear All Files…" : "Clear Selected Files…"
    }
    public var canClear: Bool {
        !busy && (selection.isEmpty ? (chosenApplet?.canWrite == true && !(chosenApplet?.files.isEmpty ?? true)) :
                  selectedFiles.count == selection.count && selectedFiles.allSatisfy { applet(for: $0.id)?.canWrite == true })
    }
    public var importApplet: NeoApplet? {
        if selection.count == 1, let file = selectedFiles.first { return applet(for: file.id) }
        return selection.isEmpty ? chosenApplet : nil
    }
    public var canImport: Bool { !busy && importApplet?.canWrite == true }
    public var stopRequest: StopRequest?
    private var monitor: Task<Void, Never>?
    private var epoch = 0
    private let monitoringEnabled: Bool

    public init(service: DeviceService = DeviceService(), preferences: Preferences? = nil, monitoringEnabled: Bool = true) {
        self.service = service; self.preferences = preferences ?? Preferences(); self.monitoringEnabled = monitoringEnabled
    }
    public func applet(for id: NeoFileID) -> NeoApplet? {
        devices.first { $0.connection == id.connection }?.applets.first { $0.id == id.applet }
    }
    public func start() {
        guard monitoringEnabled, monitor == nil, !shuttingDown else { return }
        monitor = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if !self.busy {
                    let observed = self.epoch
                    do {
                        let result = try await self.service.scan()
                        // A scan queued before a user operation must not replace its newer result.
                        if observed == self.epoch && !self.busy {
                            self.devices = result.devices; self.connectionIssue = result.issue
                            self.reconcileSelection()
                        }
                    } catch { self.connectionIssue = error.localizedDescription }
                }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }
    public func reconcileSelection() {
        if let sidebar {
            if let device = devices.first(where: { $0.connection == sidebar.connection }) {
                if case .applet(_, let id) = sidebar,
                   !device.applets.contains(where: { $0.id == id && (preferences.filter.appletIDs?.contains(id) ?? true) }) {
                    self.sidebar = nil
                }
            } else { self.sidebar = nil }
        }
        if sidebar == nil, let device = devices.first {
            if let applet = device.applets.first(where: { preferences.filter.appletIDs?.contains($0.id) ?? true }) {
                sidebar = .applet(device.connection, applet.id)
            } else { sidebar = .device(device.connection) }
        }
        selection.formIntersection(Set(files.map(\.id)))
    }
    private func replace(_ snapshot: NeoSnapshot) {
        if let index = devices.firstIndex(where: { $0.connection == snapshot.connection }) { devices[index] = snapshot }
        reconcileSelection()
    }
    private func run(_ title: String, _ action: @MainActor () async throws -> Void) async {
        guard !busy else { notice = AppNotice("Please wait", "Wait for the current transfer to finish, then try again."); return }
        activities += 1; epoch += 1; operationText = title
        defer { activities -= 1; operationText = ""; progress = nil; stopRequest = nil }
        do { try await action() }
        catch {
            notice = AppNotice("The operation could not be completed", error.localizedDescription)
            if let result = try? await service.refresh() { devices = result.devices; connectionIssue = result.issue; reconcileSelection() }
        }
    }
    public func refresh() async {
        await run("Refreshing files…") {
            let result = try await service.refresh()
            devices = result.devices; connectionIssue = result.issue; reconcileSelection()
        }
    }
    public func readText(_ id: NeoFileID) async throws -> String {
        guard !shuttingDown else { throw NeoError.cancelled }
        guard let applet = applet(for: id) else { throw NeoError.disconnected }
        activities += 1; epoch += 1
        defer { activities -= 1 }
        let bytes = try await service.read(id)
        return try FileCodec.text(bytes, applet: applet)
    }
    public func importFiles(_ urls: [URL]) async {
        guard let applet = importApplet, applet.canWrite, let device = chosenDevice else {
            notice = AppNotice("Choose an applet", "Choose AlphaWord or the user dictionary to add a text file, or select one of its files to replace it.")
            return
        }
        // Keep the destination fixed while an async import is running, even if the selection changes.
        let target = selectedFiles.first
        let replacing = !selection.isEmpty
        await run("Reading the text file…") {
            guard !replacing || urls.count == 1 else {
                throw NeoError.device("Choose one text file when replacing a selected Neo file.")
            }
            var created = 0
            do {
                for url in urls {
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    if let target {
                        pendingChange = try await service.prepareReplacement(file: target.id, from: url)
                    } else {
                        let value = try await service.create(connection: device.connection, appletID: applet.id, from: url)
                        created += 1; replace(value)
                    }
                }
            } catch {
                guard created > 0 else { throw error }
                let reason = error.localizedDescription.replacingOccurrences(of: " No device files were changed.", with: "")
                throw NeoError.device("\(created.formatted()) files were added before the import stopped. \(reason)")
            }
        }
    }
    public func requestClear() async {
        guard canClear, let device = chosenDevice else { return }
        let selected = selection
        let appletID: UInt16?
        if selected.isEmpty { appletID = chosenApplet?.id }
        else {
            let ids = Set(selected.map(\.applet))
            appletID = ids.count == 1 ? ids.first : nil
        }
        guard let appletID else { notice = AppNotice("Choose files from one applet", "Clear one applet’s files at a time."); return }
        await run("Reading the original files…") {
            pendingChange = try await service.prepareClear(connection: device.connection, appletID: appletID,
                                                           files: selected.isEmpty ? nil : selected)
        }
    }
    public func confirm(_ change: PreparedChange, saveRecovery: Bool) async {
        pendingChange = nil
        let options = RecoveryOptions(enabled: saveRecovery, folder: preferences.backupFolder, retentionDays: preferences.retentionDays)
        await run("Saving recovery copies and changing files…") {
            let result = try await service.apply(change, recovery: options)
            replace(result.snapshot)
        }
    }
    public func rename(_ file: NeoFileID, to name: String) async {
        await run("Renaming the file…") { replace(try await service.rename(file, to: name)) }
    }
    public func exportFiles(to folder: URL) async {
        let ids = selection.isEmpty ? files.map(\.id) : selectedFiles.map(\.id)
        guard !ids.isEmpty else { return }
        await run("Saving files to your Mac…") {
            let scoped = folder.startAccessingSecurityScopedResource()
            defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
            let outputs = try await service.export(ids, to: folder)
            notice = AppNotice("Files saved", "AlphaSync saved \(outputs.count.formatted()) files to:\n\(folder.path)\n\nThe original files on your Neo have not been changed.")
        }
    }
    public func backup() async {
        let identities = devices.map(\.connection)
        let included = preferences.filter.appletIDs, folder = preferences.backupFolder, logs = preferences.saveBackupLogs
        guard !identities.isEmpty else { return }
        await run("Starting the backup…") {
            let request = StopRequest(); stopRequest = request
            backupResult = try await service.backup(connections: identities, includedApplets: included, destination: folder,
                                                     saveLog: logs, stop: request) { [weak self] value in
                Task { @MainActor in
                    guard let self, self.stopRequest === request else { return }
                    self.operationText = value.fileName.isEmpty ? "Finishing the backup…" : "Backing up ‘\(value.fileName)’…"
                    self.progress = value.expected > 0 ? Double(value.saved) / Double(value.expected) : nil
                }
            }
        }
    }
    public func shutdown() async {
        shuttingDown = true
        monitor?.cancel(); monitor = nil
        stopRequest?.stop()
        while activities > 0 { try? await Task.sleep(for: .milliseconds(50)) }
        await service.shutdown()
    }
}
