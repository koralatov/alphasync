import SwiftUI
import AppKit
import AlphaSyncCore
import AlphaSyncHardware

struct DictionaryImportConfirmation: View {
    let request: DictionaryImportRequest
    let cancel: () -> Void
    let confirm: () -> Void
    @FocusState private var cancelFocused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Some dictionary words cannot be imported", systemImage: "exclamationmark.triangle").font(.headline)
            Text(request.sources.first?.lastPathComponent ?? "Dictionary import").textSelection(.enabled)
            Text(request.report.explanation).fixedSize(horizontal: false, vertical: true)
            Text("Continue with only the valid words? Replacing an existing file still requires the usual Replace confirmation.")
                .fixedSize(horizontal: false, vertical: true)
            if request.completedFiles > 0 { Text("\(request.completedFiles.formatted()) files were already added and verified.").foregroundStyle(.secondary) }
            HStack {
                Spacer()
                Button("Continue", action: confirm)
                Button("Cancel", role: .cancel, action: cancel).keyboardShortcut(.defaultAction).focused($cancelFocused)
            }
        }.padding(24).frame(width: 450)
            .defaultFocus($cancelFocused, true).onAppear { cancelFocused = true }
    }
}

public struct DestructiveConfirmation: View {
    let title: String
    let action: String
    let explanation: String
    let names: [String]
    @State private var saveRecovery: Bool
    let cancel: () -> Void
    let confirm: (Bool) -> Void
    @FocusState private var cancelFocused: Bool
    public init(title: String, action: String, explanation: String, names: [String], saveRecovery: Bool,
                cancel: @escaping () -> Void, confirm: @escaping (Bool) -> Void) {
        self.title = title; self.action = action; self.explanation = explanation; self.names = names; _saveRecovery = State(initialValue: saveRecovery)
        self.cancel = cancel; self.confirm = confirm
    }
    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(title, systemImage: "exclamationmark.triangle").font(.headline)
            Text(explanation).fixedSize(horizontal: false, vertical: true)
            if names.count > 1 {
                ScrollView {
                    Text(names.joined(separator: ", ")).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.frame(maxHeight: 140)
            }
            Toggle("Save a recovery copy first", isOn: $saveRecovery)
            HStack {
                Spacer()
                Button(action, role: .destructive) { confirm(saveRecovery) }
                Button("Cancel", role: .cancel, action: cancel)
                    .keyboardShortcut(.defaultAction).focused($cancelFocused)
            }
        }
        .padding(24).frame(width: 430)
        .defaultFocus($cancelFocused, true)
        .onAppear { cancelFocused = true }
    }
}

struct RenameFile: View {
    let file: NeoFile
    @State private var name: String
    let cancel: () -> Void
    let rename: (String) -> Void
    @FocusState private var nameFocused: Bool
    init(file: NeoFile, cancel: @escaping () -> Void, rename: @escaping (String) -> Void) {
        self.file = file; _name = State(initialValue: file.displayName); self.cancel = cancel; self.rename = rename
    }
    private var valid: Bool { (try? NeoFileAttributes(name: name)) != nil }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Rename ‘\(file.displayName)’").font(.headline)
            TextField("Name:", text: $name).focused($nameFocused)
            Text("Use 1 to 15 supported characters, without control characters.").font(.callout).foregroundStyle(.secondary)
            HStack { Spacer(); Button("Cancel", role: .cancel, action: cancel); Button("Rename") { rename(name) }.keyboardShortcut(.defaultAction).disabled(!valid) }
        }.padding(24).frame(width: 400).defaultFocus($nameFocused, true)
    }
}

struct BackupCompletion: View {
    let result: BackupResult
    let close: () -> Void
    @State private var openError: String?
    private var title: String {
        if result.complete && result.expected == 0 { return "No files to back up" }
        return result.complete ? "Backup complete" : (result.stopped ? "Backup stopped" : "Backup incomplete")
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.headline)
            Text("AlphaSync saved \(result.saved.formatted()) of \(result.expected.formatted()) files. The original files on your Neo have not been changed.")
                .fixedSize(horizontal: false, vertical: true)
            if !result.failures.isEmpty {
                ScrollView { Text(result.failures.joined(separator: "\n\n")).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                    .frame(maxHeight: 140)
            }
            if !result.folders.isEmpty {
                Text("Saved to:").font(.headline)
                ForEach(result.folders, id: \.self) { folder in Text(folder.path).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) }
                Text("Open the backup folder to view your saved files in Finder.").foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                if !result.folders.isEmpty {
                    Button(result.folders.count == 1 ? "Open Backup Folder" : "Open Backup Folders") {
                        for folder in result.folders where !NSWorkspace.shared.open(folder) { openError = "The folder could not be opened at \(folder.path)." }
                    }
                }
                Button("Done", action: close).keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 500)
        .alert("The folder could not be opened", isPresented: Binding(get: { openError != nil }, set: { if !$0 { openError = nil } })) {
            Button("OK", role: .cancel) { openError = nil }
        } message: { Text(openError ?? "") }
    }
}
