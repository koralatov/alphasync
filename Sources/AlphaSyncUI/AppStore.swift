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

struct ImportTarget: Equatable, Sendable {
    let connection: UUID
    let applet: UInt16
    let file: NeoFileID?
}

struct InspectorPreviewID: Hashable, Sendable {
    let file: NeoFileID
    let revision: UUID
}

struct DictionaryImportRequest: Identifiable {
    let id = UUID()
    let sources: [URL]
    let target: ImportTarget
    let sourceText: String
    let report: DictionaryImportReport
    let completedFiles: Int
}

enum FileConfirmation: Identifiable {
    case change(PreparedChange)
    case dictionary(DictionaryImportRequest)
    var id: UUID {
        switch self { case .change(let value): return value.id; case .dictionary(let value): return value.id }
    }
}

@MainActor
public final class AppStore: ObservableObject {
    @Published public var devices: [NeoSnapshot] = []
    @Published public var sidebar: SidebarSelection?
    @Published public var selection = Set<NeoFileID>()
    @Published public var notice: AppNotice?
    @Published var fileConfirmation: FileConfirmation? { didSet { resumeAttachmentScan() } }
    public var pendingChange: PreparedChange? {
        get { if case .change(let change) = fileConfirmation { return change }; return nil }
        set { fileConfirmation = newValue.map(FileConfirmation.change) }
    }
    var pendingDictionaryImport: DictionaryImportRequest? {
        if case .dictionary(let request) = fileConfirmation { return request }
        return nil
    }
    @Published public var backupResult: BackupResult?
    @Published public private(set) var lastExportedFiles: [URL] = []
    @Published public var operationText = ""
    @Published public var progress: Double?
    @Published public var connectionIssue: String?
    @Published public var showImporter = false
    @Published public var showExportFolder = false
    @Published public private(set) var shuttingDown = false
    @Published private var contentRevision = UUID()
    @Published private var activities = 0
    public let preferences: Preferences
    public let service: DeviceService
    public let temporaryExports = TemporaryExports()
    public var busy: Bool { activities > 0 || shuttingDown || fileConfirmation != nil }
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
    var inspectorPreviewID: InspectorPreviewID? {
        guard selection.count == 1, let file = selectedFiles.first else { return nil }
        return InspectorPreviewID(file: file.id, revision: contentRevision)
    }
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
    private var scanTask: Task<Void, Never>?
    private var scanPending = false
    private var monitorGeneration = UUID()
    private var monitoringIssue: String?
    private var discoveryIssue: String?
    private var epoch = 0
    private let monitoringEnabled: Bool
    private var importRequest: ImportTarget?
    private var exportRequest: [NeoFileID]?

    public init(service: DeviceService = DeviceService(), preferences: Preferences? = nil, monitoringEnabled: Bool = true) {
        self.service = service; self.preferences = preferences ?? Preferences(); self.monitoringEnabled = monitoringEnabled
    }
    deinit { monitor?.cancel(); scanTask?.cancel() }
    public func applet(for id: NeoFileID) -> NeoApplet? {
        devices.first { $0.connection == id.connection }?.applets.first { $0.id == id.applet }
    }
    public func start() {
        guard monitoringEnabled, monitor == nil, !shuttingDown else { return }
        let observer = service.attachmentMonitor()
        let generation = UUID()
        monitorGeneration = generation
        monitoringIssue = nil
        updateConnectionIssue()
        monitor = Task { [weak self] in
            defer {
                observer.cancel()
                if self?.monitorGeneration == generation { self?.monitor = nil }
            }
            do {
                for try await _ in observer.events {
                    guard !Task.isCancelled, let self else { return }
                    self.scanPending = true
                    self.resumeAttachmentScan()
                }
            } catch {
                if !Task.isCancelled {
                    self?.monitoringIssue = error.localizedDescription
                    self?.updateConnectionIssue()
                }
            }
        }
    }
    private func resumeAttachmentScan() {
        guard monitoringEnabled, scanPending, scanTask == nil, !busy, !shuttingDown else { return }
        scanPending = false
        scanTask = Task { [weak self] in
            guard let self else { return }
            defer { self.scanTask = nil; self.resumeAttachmentScan() }
            guard !self.busy, !self.shuttingDown else { self.scanPending = true; return }
            let observed = self.epoch
            do {
                let result = try await self.service.scan()
                guard !Task.isCancelled, !self.shuttingDown else { return }
                if observed == self.epoch && !self.busy {
                    self.devices = result.devices; self.discoveryIssue = result.issue
                    self.updateConnectionIssue()
                    self.reconcileSelection()
                } else { self.scanPending = true }
            } catch {
                if !Task.isCancelled && !self.shuttingDown {
                    self.discoveryIssue = error.localizedDescription
                    self.updateConnectionIssue()
                }
            }
        }
    }
    private func updateConnectionIssue() {
        let messages = [monitoringIssue, discoveryIssue].compactMap { $0 }
        connectionIssue = messages.isEmpty ? nil : messages.joined(separator: "\n\n")
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
        contentRevision = UUID()
        reconcileSelection()
    }
    private func run(_ title: String, _ action: @MainActor () async throws -> Void) async {
        guard !busy else {
            notice = AppNotice("Please wait", "Wait for the current transfer to finish, then try again.")
            return
        }
        activities += 1
        epoch += 1
        operationText = title
        defer {
            activities -= 1
            operationText = ""
            progress = nil
            stopRequest = nil
            resumeAttachmentScan()
        }
        do { try await action() }
        catch {
            if error is CancellationError { return }
            notice = AppNotice("The operation could not be completed", error.localizedDescription)
            if let result = try? await service.refresh() {
                devices = result.devices
                contentRevision = UUID()
                discoveryIssue = result.issue
                updateConnectionIssue()
                reconcileSelection()
            }
        }
    }
    public func refresh() async {
        await run("Refreshing files…") {
            let result = try await service.refresh(retryConnections: true)
            devices = result.devices; discoveryIssue = result.issue
            updateConnectionIssue()
            contentRevision = UUID()
            reconcileSelection()
        }
        start()
    }
    public func readText(_ id: NeoFileID) async throws -> String {
        try Task.checkCancellation()
        guard !shuttingDown else { throw NeoError.cancelled }
        guard let applet = applet(for: id) else { throw NeoError.disconnected }
        activities += 1
        epoch += 1
        defer { activities -= 1; resumeAttachmentScan() }
        let bytes = try await service.read(id)
        try Task.checkCancellation()
        return try FileCodec.text(bytes, applet: applet)
    }
    private func importTarget(replacing file: NeoFileID? = nil) -> ImportTarget? {
        guard !busy else { return nil }
        if let file {
            guard let applet = applet(for: file), applet.canWrite,
                  applet.files.contains(where: { $0.id == file }) else { return nil }
            return ImportTarget(connection: file.connection, applet: file.applet, file: file)
        }
        guard canImport, let applet = importApplet, let device = chosenDevice,
              selection.isEmpty || selectedFiles.count == 1 else { return nil }
        return ImportTarget(connection: device.connection, applet: applet.id, file: selectedFiles.first?.id)
    }
    public func beginImport() {
        guard !showImporter, !showExportFolder, let target = importTarget() else { return }
        importRequest = target
        showImporter = true
    }
    @discardableResult
    public func finishImport(_ result: Result<[URL], Error>) -> Task<Void, Never>? {
        let target = importRequest
        importRequest = nil
        showImporter = false
        guard let target else { return nil }
        switch result {
        case .success(let urls): return Task { await importFiles(urls, to: target) }
        case .failure(let error):
            if (error as NSError).code != NSUserCancelledError {
                notice = AppNotice("The file could not be opened", error.localizedDescription)
            }
            return nil
        }
    }
    @discardableResult
    func importDroppedFiles(_ urls: [URL], replacing file: NeoFileID? = nil) -> Task<Void, Never>? {
        guard !urls.isEmpty, let target = importTarget(replacing: file) else { return nil }
        if let file { selection = [file] }
        return Task { await importFiles(urls, to: target) }
    }
    private func importFiles(_ urls: [URL], to target: ImportTarget, dictionaryConsent: String? = nil, previouslyCreated: Int = 0) async {
        let replacing = target.file != nil
        await run("Reading the text file…") {
            var created = previouslyCreated
            do {
                guard let applet = devices.first(where: { $0.connection == target.connection })?.applets.first(where: { $0.id == target.applet }),
                      applet.canWrite, target.file.map({ id in applet.files.contains { $0.id == id } }) ?? true else {
                    throw NeoError.disconnected
                }
                guard !replacing || urls.count == 1 else {
                    throw NeoError.device("Choose one text file when replacing a selected Neo file.")
                }
                for (offset, url) in urls.enumerated() {
                    try Task.checkCancellation()
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    do {
                        let consent = offset == 0 ? dictionaryConsent : nil
                        if let file = target.file {
                            pendingChange = try await service.prepareReplacement(file: file, from: url, dictionaryConsent: consent)
                        } else {
                            let value = try await service.create(connection: target.connection, appletID: target.applet, from: url, dictionaryConsent: consent)
                            created += 1; replace(value)
                        }
                    } catch let warning as DictionaryImportWarning {
                        fileConfirmation = .dictionary(DictionaryImportRequest(sources: Array(urls.dropFirst(offset)), target: target,
                            sourceText: warning.sourceText, report: warning.report, completedFiles: created))
                        return
                    }
                }
            } catch {
                throw OperationFailure(error, action: replacing ? .change : .add, completedFiles: created)
            }
        }
    }
    func confirmDictionaryImport(_ request: DictionaryImportRequest) async {
        fileConfirmation = nil
        await importFiles(request.sources, to: request.target, dictionaryConsent: request.sourceText, previouslyCreated: request.completedFiles)
    }
    func cancelDictionaryImport(_ request: DictionaryImportRequest) {
        fileConfirmation = nil
        if request.completedFiles > 0 {
            notice = AppNotice("Import stopped", request.completedFiles == 1 ? "One file was already added and verified. It has been kept on your Neo." : "\(request.completedFiles.formatted()) files were already added and verified. Those files have been kept on your Neo.")
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
        await run("Saving recovery copies and changing files…") {
            let folder = saveRecovery ? try preferences.prepareBackupFolder() : preferences.backupFolder
            let scoped = saveRecovery && folder.startAccessingSecurityScopedResource()
            defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
            let options = RecoveryOptions(enabled: saveRecovery, folder: folder, retentionDays: preferences.retentionDays)
            let result = try await service.apply(change, recovery: options)
            replace(result.snapshot)
        }
    }
    public func rename(_ file: NeoFileID, to name: String) async {
        await run("Renaming the file…") { replace(try await service.rename(file, to: name)) }
    }
    public func beginExport() {
        guard !busy, !showImporter, !showExportFolder else { return }
        let ids = selection.isEmpty ? files.map(\.id) : selectedFiles.map(\.id)
        guard !ids.isEmpty, selection.isEmpty || ids.count == selection.count else { return }
        exportRequest = ids
        showExportFolder = true
    }
    @discardableResult
    public func finishExport(_ result: Result<URL, Error>) -> Task<Void, Never>? {
        let ids = exportRequest
        exportRequest = nil
        showExportFolder = false
        guard let ids else { return nil }
        switch result {
        case .success(let folder): return Task { await exportFiles(ids, to: folder) }
        case .failure(let error):
            if (error as NSError).code != NSUserCancelledError {
                notice = AppNotice("The folder could not be opened", error.localizedDescription)
            }
            return nil
        }
    }
    private func exportFiles(_ ids: [NeoFileID], to folder: URL) async {
        await run("Saving files to your Mac…") {
            lastExportedFiles = []
            guard ids.allSatisfy({ id in applet(for: id)?.files.contains { $0.id == id } == true }) else {
                throw NeoError.disconnected
            }
            let scoped = folder.startAccessingSecurityScopedResource()
            defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
            do {
                lastExportedFiles = try await service.export(ids, to: folder)
                notice = AppNotice("Files saved", "AlphaSync saved \(lastExportedFiles.count.formatted()) files to:\n\(folder.path)\n\nThe original files on your Neo have not been changed.")
            } catch let failure as ExportFailure {
                lastExportedFiles = failure.savedFiles
                throw failure
            }
        }
    }
    public func backup() async {
        let identities = devices.map(\.connection)
        let included = preferences.filter.appletIDs, logs = preferences.saveBackupLogs
        guard !identities.isEmpty else { return }
        await run("Starting the backup…") {
            let folder = try preferences.prepareBackupFolder()
            let scoped = folder.startAccessingSecurityScopedResource()
            defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
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
        monitor?.cancel()
        monitor = nil
        scanTask?.cancel()
        scanPending = false
        stopRequest?.stop()
        while activities > 0 {
            try? await Task.sleep(for: .milliseconds(50))
        }
        await service.shutdown()
    }
}
