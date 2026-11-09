import SwiftUI
import AppKit
import UniformTypeIdentifiers
import AlphaSyncCore

public struct AboutView: View {
    private enum AboutLink: Hashable { case project, release, licence }
    @FocusState private var focusedLink: AboutLink?
    public init() {}
    @MainActor
    private var bundledIcon: NSImage {
        // Load the selected artwork without the system application icon’s additional presentation.
        if let file = Bundle.main.object(forInfoDictionaryKey: "CFBundleIconFile") as? String,
           let url = Bundle.main.url(forResource: (file as NSString).deletingPathExtension, withExtension: "icns"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        return NSApp.applicationIconImage
    }
    public var body: some View {
        VStack(spacing: 20) {
            Image(nsImage: bundledIcon).renderingMode(.original).resizable().scaledToFit().frame(width: 96, height: 96).accessibilityHidden(true)
            VStack(spacing: 6) {
                Text("AlphaSync").font(.largeTitle.bold())
                Text("Version \(AppMetadata.version) (\(AppMetadata.build))")
                Text(AppMetadata.compatibility).foregroundStyle(.secondary)
            }
            Text("Transfer and back up\nAlphaSmart Neo files.").multilineTextAlignment(.center)
            Divider()
            Text("Copyright © tSoniq 2009–2013.\nAll rights reserved.").font(.callout).multilineTextAlignment(.center)
            Text("Original application by tSoniq\nMaintained by Koralatov").font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            HStack {
                Link("Project", destination: AppMetadata.project).focused($focusedLink, equals: .project)
                Spacer()
                Link("Release notes", destination: AppMetadata.releaseNotes).focused($focusedLink, equals: .release)
                Spacer()
                Button("Licence") { AppActions.licence() }.buttonStyle(.link).focused($focusedLink, equals: .licence)
            }
        }.padding(32).frame(width: 420).fixedSize(horizontal: false, vertical: true)
            .defaultFocus($focusedLink, nil).onAppear { focusedLink = nil }
    }
}

public struct SettingsView: View {
    @ObservedObject private var preferences: Preferences
    @State private var choosingFolder = false
    @State private var folderError: String?
    public init(preferences: Preferences) { self.preferences = preferences }
    public var body: some View {
        Form {
            Section("Files shown and backed up") {
                Picker("Show:", selection: $preferences.filter) { ForEach(FileFilter.allCases) { Text($0.title).tag($0) } }
            }
            Section("Backups") {
                LabeledContent("Save to:") {
                    HStack {
                        Text(preferences.backupFolder.path).lineLimit(2).textSelection(.enabled).help(preferences.backupFolder.path)
                        Button("Choose…") { choosingFolder = true }
                    }
                }
                if let issue = preferences.backupLocationIssue { Text(issue).font(.callout).foregroundStyle(.secondary).textSelection(.enabled) }
                Toggle("Save a backup log", isOn: $preferences.saveBackupLogs)
                Text("Logs are off unless you enable them. Each log stays inside its dated backup folder.").font(.callout).foregroundStyle(.secondary)
            }
            Section("Recovery copies") {
                Toggle("Save recovery copies by default", isOn: $preferences.saveRecoveryCopies)
                Picker("Keep copies:", selection: $preferences.retentionDays) {
                    Text("7 days").tag(7); Text("30 days").tag(30); Text("90 days").tag(90); Text("Until I remove them").tag(0)
                }
                Button("Open Recovery Copies") {
                    do { AppActions.openFolder(try preferences.resolvedBackupFolder().appendingPathComponent("Recovery Copies", isDirectory: true)) }
                    catch { folderError = error.localizedDescription }
                }
                Text("Original text and raw Neo bytes are saved before replacement or clearing. A failed requested copy stops the change. Expired recognised copies move to Trash when a new copy is made.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section("Automatic opening") {
                Toggle("Open AlphaSync when a Neo is connected", isOn: Binding(get: { preferences.automaticOpening }, set: { preferences.setAutomaticOpening($0) }))
                Text(preferences.loginStatus).font(.callout).foregroundStyle(.secondary)
                Button("Open Login Items Settings") { preferences.openLoginSettings() }
            }
        }.formStyle(.grouped).frame(width: 560).frame(minHeight: 500, idealHeight: 610, maxHeight: 700)
            .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder]) { result in
                do {
                    let url = try result.get()
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    try preferences.selectBackupFolder(url)
                } catch {
                    if (error as NSError).code != NSUserCancelledError { folderError = error.localizedDescription }
                }
            }
            .alert("The backup folder could not be opened", isPresented: Binding(get: { folderError != nil }, set: { if !$0 { folderError = nil } })) {
                Button("OK", role: .cancel) { folderError = nil }
            } message: { Text(folderError ?? "") }
            .onAppear { preferences.refreshLoginStatus(); _ = try? preferences.resolvedBackupFolder() }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                preferences.refreshLoginStatus()
                _ = try? preferences.resolvedBackupFolder()
            }
    }
}

public struct InspectorView: View {
    @ObservedObject private var store: AppStore
    @State private var preview: String?
    @State private var previewError: String?
    public init(store: AppStore) { self.store = store }
    private var file: NeoFile? { store.selection.count == 1 ? store.selectedFiles.first : nil }
    public var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: file == nil ? "gearshape" : "doc.text").font(.system(size: 40)).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 6) {
                    Text(file?.displayName ?? store.chosenApplet?.name ?? store.chosenDevice?.name ?? "No selection").font(.headline)
                    Text(file.flatMap { store.applet(for: $0.id)?.name } ?? store.chosenApplet?.version ?? "")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let size = file?.size { Text(FileSize.compact(size)).bold() }
            }.padding(18)
            Divider()
            Form {
                Section("More Information") {
                    if let file {
                        LabeledContent("Kind:", value: FileCodec.fileExtension(applet: file.id.applet) == "txt" ? "Text file" : "Applet data")
                        LabeledContent("Size:", value: FileSize.exact(file.size))
                        LabeledContent("RAM usage:", value: FileSize.exact(file.allocation))
                        LabeledContent("Bound to key:", value: file.fileSpace > 0 ? "F\(file.fileSpace)" : "Unbound")
                        LabeledContent("Password:", value: file.password)
                    } else if let applet = store.chosenApplet {
                        LabeledContent("Version:", value: applet.version)
                        LabeledContent("Files:", value: applet.files.count.formatted())
                        LabeledContent("Minimum file size:", value: applet.limits.map { FileSize.exact($0.minimum) } ?? "Unavailable")
                        LabeledContent("Maximum file size:", value: applet.limits.map { FileSize.exact($0.maximum) } ?? "Unavailable")
                        LabeledContent("ROM used:", value: FileSize.exact(applet.romSize))
                        LabeledContent("RAM used:", value: FileSize.exact(applet.ramUsed))
                        Text(applet.information).textSelection(.enabled)
                    } else if let device = store.chosenDevice {
                        LabeledContent("System version:", value: device.systemVersion)
                        LabeledContent("Available RAM:", value: FileSize.exact(device.availableRAM))
                        LabeledContent("Available ROM:", value: FileSize.exact(device.availableROM))
                    } else { Text("Select a file, applet, or Neo to see its information.").foregroundStyle(.secondary) }
                }
                Section("Preview") {
                    if let preview { Text(preview).textSelection(.enabled).lineLimit(12).frame(maxWidth: .infinity, alignment: .leading) }
                    else if let previewError { Text(previewError).foregroundStyle(.secondary) }
                    else if file != nil { ProgressView("Reading preview…") }
                    else { Image(systemName: "gearshape").font(.system(size: 80)).frame(maxWidth: .infinity).foregroundStyle(.secondary) }
                }
            }.formStyle(.grouped).textSelection(.enabled)
        }.frame(width: 400).frame(minHeight: 430, idealHeight: 560, maxHeight: 700)
            .task(id: store.inspectorPreviewID) {
                preview = nil; previewError = nil
                guard let request = store.inspectorPreviewID else { return }
                do {
                    let text = try await store.readText(request.file)
                    if !Task.isCancelled { preview = String(text.prefix(2048)) }
                } catch { if !Task.isCancelled { previewError = error.localizedDescription } }
            }
    }
}
