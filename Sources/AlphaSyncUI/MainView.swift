import SwiftUI
import UniformTypeIdentifiers
import CoreTransferable
import AlphaSyncCore
import AlphaSyncHardware

public struct MainView: View {
    @ObservedObject private var store: AppStore
    @ObservedObject private var preferences: Preferences
    @Environment(\.openWindow) private var openWindow
    @State private var renaming: NeoFile?

    public init(store: AppStore) { self.store = store; preferences = store.preferences }

    public var body: some View {
        Group {
            if store.connected { fileManager }
            else { waiting }
        }
        .frame(minWidth: store.connected ? 760 : 360, idealWidth: store.connected ? 820 : 360,
               maxWidth: store.connected ? .infinity : 360,
               minHeight: store.connected ? 460 : 230, idealHeight: store.connected ? 560 : 230,
               maxHeight: store.connected ? .infinity : 230)
        .navigationTitle("AlphaSync")
        .toolbar {
            if store.connected {
                ToolbarItemGroup {
                    Button { Task { await store.backup() } } label: { Label("Backup", systemImage: "externaldrive") }
                        .help("Back up the files shown from connected Neos").disabled(store.busy)
                    Button { Task { await store.requestClear() } } label: { Label(store.clearTitle, systemImage: "trash") }
                        .help(store.selection.isEmpty ? "Clear all files in the selected applet" : "Clear only the selected files")
                        .disabled(!store.canClear)
                    Button { openWindow(id: "inspector") } label: { Label("Info", systemImage: "info.circle") }
                        .help("Show information about the selection")
                    Button { Task { await store.refresh() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                        .disabled(store.busy)
                }
            }
        }
        .fileImporter(isPresented: $store.showImporter, allowedContentTypes: [.plainText], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): Task { await store.importFiles(urls) }
            case .failure(let error): store.notice = AppNotice("The file could not be opened", error.localizedDescription)
            }
        }
        .fileImporter(isPresented: $store.showExportFolder, allowedContentTypes: [.folder]) { result in
            switch result {
            case .success(let url): Task { await store.exportFiles(to: url) }
            case .failure(let error): store.notice = AppNotice("The folder could not be opened", error.localizedDescription)
            }
        }
        .sheet(item: $store.pendingChange) { change in
            DestructiveConfirmation(title: change.title, action: change.action, explanation: change.explanation,
                                    names: change.items.map { $0.file.displayName }, saveRecovery: preferences.saveRecoveryCopies,
                               cancel: { store.pendingChange = nil },
                               confirm: { choice in Task { await store.confirm(change, saveRecovery: choice) } })
        }
        .sheet(isPresented: Binding(get: { store.backupResult != nil }, set: { if !$0 { store.backupResult = nil } })) {
            if let result = store.backupResult { BackupCompletion(result: result, close: { store.backupResult = nil }) }
        }
        .sheet(item: $renaming) { file in
            RenameFile(file: file, cancel: { renaming = nil }, rename: { name in
                renaming = nil; Task { await store.rename(file.id, to: name) }
            })
        }
        .alert(item: $store.notice) { notice in Alert(title: Text(notice.title), message: Text(notice.message), dismissButton: .default(Text("OK"))) }
        .onChange(of: store.sidebar) { _ in store.selection = [] }
        .onChange(of: preferences.filter) { _ in store.reconcileSelection() }
        .task { store.start(); store.reconcileSelection() }
    }

    private var waiting: some View {
        VStack(spacing: 14) {
            Image(systemName: "cable.connector").font(.system(size: 42)).foregroundStyle(.secondary).accessibilityHidden(true)
            Text("No Neo connected").font(.title2.weight(.semibold))
            Text(store.connectionIssue ?? "Connect your AlphaSmart Neo with a USB cable. Its files will appear here.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if store.connectionIssue != nil {
                Button("Try Again") { Task { await store.refresh() } }.disabled(store.busy)
            }
        }.padding(24)
    }
    private var fileManager: some View {
        NavigationSplitView {
            List(selection: $store.sidebar) {
                ForEach(store.devices, id: \.connection) { device in
                    Section {
                        Label("All Files", systemImage: "doc.on.doc").tag(SidebarSelection.device(device.connection))
                        ForEach(device.applets.filter { preferences.filter.appletIDs?.contains($0.id) ?? true }) { applet in
                            Label(applet.name.isEmpty ? "Applet \(String(format: "0x%04X", applet.id))" : applet.name, systemImage: "gearshape")
                                .tag(SidebarSelection.applet(device.connection, applet.id))
                        }
                    } header: { Label(device.name, systemImage: "externaldrive.connected.to.line.below") }
                }
            }.listStyle(.sidebar).navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 300)
        } detail: {
            Table(store.files, selection: $store.selection) {
                TableColumn("Name") { file in
                    Label(file.displayName, systemImage: "doc.text")
                        .draggable(FileDrag(file: file.id, service: store.service, folder: store.temporaryExports))
                        .dropDestination(for: URL.self) { urls, _ in
                            guard !store.busy, !urls.isEmpty, store.applet(for: file.id)?.canWrite == true else { return false }
                            store.selection = [file.id]
                            Task { await store.importFiles(urls) }
                            return true
                        }
                }.width(min: 200, ideal: 360)
                TableColumn("Size") { file in
                    Text(FileSize.compact(file.size)).monospacedDigit().frame(maxWidth: .infinity, alignment: .trailing)
                }.width(min: 90, ideal: 110, max: 160)
            }
            .contextMenu(forSelectionType: NeoFileID.self) { ids in
                Button("Open Read-only") { openReaders(ids) }.disabled(ids.isEmpty)
                Button("Save to Mac…") { store.showExportFolder = true }.disabled(ids.isEmpty || store.busy)
                Button("Rename…") { renaming = store.files.first { ids.contains($0.id) } }
                    .disabled(ids.count != 1 || store.busy || !ids.allSatisfy { store.applet(for: $0)?.canWrite == true })
                Divider()
                Button(store.clearTitle, role: .destructive) { Task { await store.requestClear() } }.disabled(!store.canClear)
            } primaryAction: { ids in openReaders(ids) }
            .dropDestination(for: URL.self) { urls, _ in
                guard store.canImport, !urls.isEmpty else { return false }
                Task { await store.importFiles(urls) }
                return true
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                Divider()
                HStack(spacing: 10) {
                    Label("Connected", systemImage: "circle.fill").labelStyle(.titleAndIcon).foregroundStyle(.secondary)
                    if store.busy {
                        ProgressView().controlSize(.small)
                        Text(store.operationText).lineLimit(1)
                        if let value = store.progress { ProgressView(value: value).frame(width: 90) }
                        if let stop = store.stopRequest { Button("Stop") { stop.stop() }.keyboardShortcut(.cancelAction) }
                    }
                    Spacer()
                    if let memory = store.chosenDevice?.availableRAM { Text("\(FileSize.compact(memory)) available").foregroundStyle(.secondary) }
                }.font(.callout).padding(.horizontal, 12).padding(.vertical, 7)
            }.background(.bar)
        }
    }
    private func openReaders(_ ids: Set<NeoFileID>) {
        for file in store.files where ids.contains(file.id) { openWindow(value: ReaderRequest(file: file)) }
    }
}

public enum FileSize {
    public static func compact(_ value: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file; formatter.allowedUnits = [.useBytes, .useKB]
        formatter.allowsNonnumericFormatting = false
        return formatter.string(fromByteCount: Int64(value))
    }
    public static func exact(_ value: Int) -> String { "\(value.formatted()) bytes" }
}

private struct FileDrag: Transferable, Sendable {
    let file: NeoFileID
    let service: DeviceService
    let folder: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .plainText) { item in
            let temporary = try AtomicFileStore.createFolder(in: item.folder, name: UUID().uuidString)
            let urls = try await item.service.export([item.file], to: temporary)
            guard let url = urls.first else { throw NeoError.device("The file could not be exported.") }
            return SentTransferredFile(url)
        }
    }
}
