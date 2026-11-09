import SwiftUI

@MainActor
public struct AlphaSyncCommands: Commands {
    @ObservedObject private var store: AppStore
    @Environment(\.openWindow) private var openWindow
    public init(store: AppStore) { self.store = store }
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
                Button("Find…") { AppActions.find(.showFindPanel) }.keyboardShortcut("f")
                Button("Find Next") { AppActions.find(.next) }.keyboardShortcut("g")
                Button("Find Previous") { AppActions.find(.previous) }.keyboardShortcut("g", modifiers: [.command, .shift])
                Button("Use Selection for Find") { AppActions.find(.setFindString) }.keyboardShortcut("e")
            }
        }
        CommandGroup(after: .sidebar) {
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
