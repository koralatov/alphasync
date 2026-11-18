import SwiftUI
import AppKit
import AlphaSyncCore
import AlphaSyncHardware

struct DroppedImportConfirmation: View {
    let request: DroppedImportRequest
    let cancel: () -> Void
    let confirm: () -> Void
    @FocusState private var cancelFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(request.sources.count == 1 ? "Add a new file?" : "Add \(request.sources.count.formatted()) new files?")
                .font(.headline).accessibilityAddTraits(.isHeader)
            Text("Add to \(request.destination).").fixedSize(horizontal: false, vertical: true)
            ScrollView {
                Text(request.sources.map(\.lastPathComponent).joined(separator: "\n"))
                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            }.frame(maxHeight: 140)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: cancel)
                    .keyboardShortcut(.cancelAction).focused($cancelFocused)
                Button(request.sources.count == 1 ? "Add File" : "Add Files", action: confirm)
            }
        }.padding(24).frame(width: 450)
            .defaultFocus($cancelFocused, true).onAppear { cancelFocused = true }
    }
}

struct DictionaryImportConfirmation: View {
    let request: DictionaryImportRequest
    let cancel: () -> Void
    let confirm: () -> Void
    @FocusState private var cancelFocused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Some dictionary words cannot be imported", systemImage: "exclamationmark.triangle").font(.headline).accessibilityAddTraits(.isHeader)
            Text(request.sources.first?.lastPathComponent ?? "Dictionary import").textSelection(.enabled)
            Text(request.report.explanation).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            Text("Continue with only the valid words?  Replacing an existing file still requires the usual Replace confirmation.")
                .fixedSize(horizontal: false, vertical: true)
            if request.completedFiles > 0 { Text(request.completedFiles == 1 ? "One file was already added and verified." : "\(request.completedFiles.formatted()) files were already added and verified.").foregroundStyle(.secondary) }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: cancel).keyboardShortcut(.cancelAction).focused($cancelFocused)
                Button("Continue", action: confirm)
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
            Label(title, systemImage: "exclamationmark.triangle").font(.headline).accessibilityAddTraits(.isHeader)
            Text(explanation).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            if names.count > 1 {
                ScrollView {
                    Text(names.joined(separator: "\n")).textSelection(.enabled).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.frame(maxHeight: 140)
            }
            Toggle("Save a copy of the text first", isOn: $saveRecovery)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: cancel)
                    .keyboardShortcut(.cancelAction).focused($cancelFocused)
                Button(action, role: .destructive) { confirm(saveRecovery) }
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
    private var validationMessage: String? {
        guard !name.isEmpty else { return "Enter a file name." }
        do { _ = try NeoFileAttributes(name: name); return nil }
        catch { return error.localizedDescription }
    }
    private var canRename: Bool { name != file.displayName && validationMessage == nil }
    private var guidance: String {
        if let validationMessage { return validationMessage }
        if name == file.displayName { return "Enter a different name to rename this file." }
        return "Use 1 to 15 supported characters, without control characters."
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Rename ‘\(file.displayName)’").font(.headline).accessibilityAddTraits(.isHeader)
            TextField("Name:", text: $name).focused($nameFocused)
                .accessibilityLabel("File name").accessibilityHint(guidance)
            Text(guidance).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: cancel).keyboardShortcut(.cancelAction)
                Button("Rename") { rename(name) }.keyboardShortcut(.defaultAction).disabled(!canRename)
            }
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
            Text(title).font(.headline).accessibilityAddTraits(.isHeader)
            Text("AlphaSync saved \(result.saved.formatted()) of \(result.expected.formatted()) \(result.expected == 1 ? "file" : "files").  The original files on your Neo have not been changed.")
                .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            if !result.failures.isEmpty {
                ScrollView { Text(result.failures.joined(separator: "\n\n")).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                    .frame(maxHeight: 140)
            }
            if !result.folders.isEmpty {
                Text("Saved to:").font(.headline).accessibilityAddTraits(.isHeader)
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
