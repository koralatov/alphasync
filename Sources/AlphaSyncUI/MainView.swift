import SwiftUI
import UniformTypeIdentifiers
import AppKit
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
                ToolbarItem {
                    Button { Task { await store.backup() } } label: { Label("Back Up", systemImage: "externaldrive") }
                        .help("Back up the files shown from connected Neos").disabled(store.busy)
                }
                ToolbarItem {
                    Button { Task { await store.requestClear() } } label: { Label("Clear Files", systemImage: "trash") }
                        .accessibilityLabel(store.clearTitle)
                        .help(store.selection.isEmpty ? "Clear all files in the selected applet" : "Clear only the selected files")
                        .disabled(!store.canClear)
                }
                ToolbarItem {
                    Button { openWindow(id: "inspector") } label: { Label("Inspector", systemImage: "info.circle") }
                        .help("Show information about the selection")
                }
                ToolbarItem {
                    Button { Task { await store.refresh() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                        .help("Read the current files from connected Neos")
                        .disabled(store.busy)
                }
            }
        }
        .background(ToolbarAppearanceController(preferences: preferences, connected: store.connected).frame(width: 0, height: 0))
        .fileImporter(isPresented: $store.showImporter, allowedContentTypes: [.plainText], allowsMultipleSelection: true) { result in
            store.finishImport(result)
        }
        .fileImporter(isPresented: $store.showExportFolder, allowedContentTypes: [.folder]) { result in
            store.finishExport(result)
        }
        .sheet(item: $store.fileConfirmation) { confirmation in
            switch confirmation {
            case .change(let change):
                DestructiveConfirmation(title: change.title, action: change.action, explanation: change.explanation,
                                    names: change.items.map { $0.file.displayName }, saveRecovery: preferences.saveRecoveryCopies,
                               cancel: { store.pendingChange = nil },
                               confirm: { choice in Task { await store.confirm(change, saveRecovery: choice) } })
            case .dictionary(let request):
                DictionaryImportConfirmation(request: request, cancel: { store.cancelDictionaryImport(request) },
                                             confirm: { Task { await store.confirmDictionaryImport(request) } })
            }
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
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)) { _ in
            store.resumeAfterWake()
        }
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
        DeviceBrowser {
            List(selection: $store.sidebar) {
                ForEach(store.devices, id: \.connection) { device in
                    Section {
                        Label(device.name, systemImage: SelectionSymbols.device)
                            .fontWeight(.semibold).foregroundStyle(.primary)
                            .accessibilityAddTraits(.isHeader).accessibilityIdentifier("neo-heading")
                        Label("All Files", systemImage: "doc.on.doc")
                            .padding(.leading, 14).tag(SidebarSelection.device(device.connection))
                        ForEach(device.applets.filter { preferences.filter.appletIDs?.contains($0.id) ?? true }) { applet in
                            Label(applet.name.isEmpty ? "Applet \(String(format: "0x%04X", applet.id))" : applet.name, systemImage: SelectionSymbols.applet(applet.id))
                                .padding(.leading, 14)
                                .tag(SidebarSelection.applet(device.connection, applet.id))
                        }
                    }
                }
            }.listStyle(.sidebar)
        } detail: {
            VStack(spacing: 0) {
                if let issue = store.connectionIssue { connectionWarning(issue) }
                fileTable
                connectionStatus
            }
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
    }
    private var fileTable: some View {
        Table(store.files, selection: $store.selection) {
            TableColumn("Name") { file in
                Label(file.displayName, systemImage: SelectionSymbols.file)
                    .draggable(FileDrag(file: file.id, service: store.service, staging: store.temporaryExports))
                    .dropDestination(for: URL.self) { urls, _ in
                        store.importDroppedFiles(urls, replacing: file.id) != nil
                    }
            }.width(min: 200, ideal: 360)
            TableColumn("Size") { file in
                Text(FileSize.compact(file.size)).monospacedDigit().frame(maxWidth: .infinity, alignment: .trailing)
            }.width(min: 90, ideal: 110, max: 160)
        }
        // The scroll view can shrink below its ideal size when a warning reserves space.
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .contextMenu(forSelectionType: NeoFileID.self) { ids in
            Button("Open Read-only") { openReaders(ids) }.disabled(ids.isEmpty)
            Button("Save to Mac…") { store.selection = ids; store.beginExport() }.disabled(ids.isEmpty || store.busy)
            Button("Rename…") { renaming = store.files.first { ids.contains($0.id) } }
                .disabled(ids.count != 1 || store.busy || !ids.allSatisfy { store.applet(for: $0)?.canWrite == true })
            Divider()
            Button(ids.count == 1 ? "Clear File…" : "Clear Selected Files…", role: .destructive) {
                store.selection = ids; Task { await store.requestClear() }
            }.disabled(store.busy || ids.isEmpty || Set(ids.map(\.applet)).count != 1 || !ids.allSatisfy { store.applet(for: $0)?.canWrite == true })
        } primaryAction: { ids in openReaders(ids) }
        .dropDestination(for: URL.self) { urls, _ in
            store.importDroppedFiles(urls) != nil
        }
    }
    private func connectionWarning(_ issue: String) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Label(issue, systemImage: "exclamationmark.triangle")
                    .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button("Try Again") { Task { await store.refresh() } }.disabled(store.busy)
            }.padding(12)
            Divider()
        }.background(.bar)
    }
    private var connectionStatus: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 10) {
                Label {
                    Text("Connected").foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "circle.fill").foregroundStyle(.green)
                }
                .accessibilityElement(children: .ignore).accessibilityLabel("Neo connected")
                .accessibilityIdentifier("neo-connection-status")
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
    public static func exact(_ value: Int) -> String { "\(value.formatted()) " + (value == 1 ? "byte" : "bytes") }
}
