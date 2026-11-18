import SwiftUI

@MainActor
public struct AlphaSyncCommands: Commands {
    @ObservedObject private var store: AppStore
    @ObservedObject private var preferences: Preferences
    @Environment(\.openWindow) private var openWindow
    @ObservedObject private var readerFind = ReaderFindRegistry.shared
    public init(store: AppStore) { self.store = store; preferences = store.preferences }
    public var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About AlphaSync") { openWindow(id: "about") }
        }
        CommandGroup(replacing: .newItem) {
            Button("Open Read-only") {
                for file in store.selectedFiles { openWindow(value: ReaderRequest(file: file)) }
            }.keyboardShortcut("o").disabled(store.selection.isEmpty)
            Button("Import Text Files to Neo…") { store.beginImport() }
                .keyboardShortcut("i", modifiers: [.command, .shift]).disabled(!store.canImport)
            Button("Save to Mac…") { store.beginExport() }
                .keyboardShortcut("s", modifiers: [.command, .shift]).disabled(store.files.isEmpty || store.busy)
            Divider()
            Button("Back Up Neo Files") { Task { await store.backup() } }.disabled(!store.connected || store.busy)
            Button(store.clearTitle) { Task { await store.requestClear() } }.disabled(!store.canClear)
        }
        CommandGroup(after: .textEditing) {
            Menu("Find") {
                Button("Find…") { readerFind.active?.perform(.showFindPanel) }.keyboardShortcut("f")
                    .disabled(readerFind.active == nil)
                Button("Find Next") { readerFind.active?.perform(.next) }.keyboardShortcut("g")
                    .disabled(readerFind.active == nil)
                Button("Find Previous") { readerFind.active?.perform(.previous) }.keyboardShortcut("g", modifiers: [.command, .shift])
                    .disabled(readerFind.active == nil)
            }
        }
        CommandGroup(replacing: .sidebar) {
            Menu("Toolbar Appearance") {
                Picker("Toolbar Appearance", selection: $preferences.toolbarAppearance) {
                    ForEach(ToolbarAppearance.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.inline)
            }
            Divider()
            Button("Show Inspector") { openWindow(id: "inspector") }.keyboardShortcut("i")
            Button("Refresh Neo Files") { Task { await store.refresh() } }.keyboardShortcut("r").disabled(!store.connected || store.busy)
        }
        CommandGroup(replacing: .help) {
            Button("AlphaSync Help") { AppActions.help() }.keyboardShortcut("?", modifiers: .command)
            Divider()
            Button("Release Notes for \(AppMetadata.version)") { AppActions.open(AppMetadata.releaseNotes) }
            Button("Licence") { AppActions.licence() }
            Divider()
            Button("AlphaSync on GitHub") { AppActions.open(AppMetadata.project) }
            Button("Report an Issue…") { AppActions.open(AppMetadata.issues) }
            Button("Contact Us…") { AppActions.open(AppMetadata.contact) }
        }
    }
}
