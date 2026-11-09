import SwiftUI
import AppKit
import AlphaSyncUI
import AlphaSyncCore

private struct CheckFailure: Error, CustomStringConvertible { let description: String }

/// This executable renders disposable sample data. It never starts USB discovery or registers a login item.
@main
@MainActor
struct InterfaceChecks {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw CheckFailure(description: message) }
    }
    static func settle() { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.35)) }
    static func descendants(_ root: NSView) -> [NSView] { [root] + root.subviews.flatMap(descendants) }
    static func window<V: View>(_ view: V, size: NSSize, title: String) -> NSWindow {
        let result = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        result.isReleasedWhenClosed = false
        result.title = title
        result.contentViewController = NSHostingController(rootView: view)
        result.setContentSize(size)
        result.center(); result.makeKeyAndOrderFront(nil)
        settle()
        return result
    }
    static func capture(_ window: NSWindow, _ name: String, to output: URL) throws {
        guard let view = window.contentView else { throw CheckFailure(description: "Missing content view") }
        view.layoutSubtreeIfNeeded(); view.displayIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw CheckFailure(description: "Cannot capture \(name)") }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let bytes = bitmap.representation(using: .png, properties: [:]) else { throw CheckFailure(description: "Cannot encode \(name)") }
        try bytes.write(to: output.appendingPathComponent(name + ".png"), options: .atomic)
    }
    static func key(_ character: String, code: UInt16, in window: NSWindow) throws {
        guard let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                          windowNumber: window.windowNumber, context: nil, characters: character,
                                          charactersIgnoringModifiers: character, isARepeat: false, keyCode: code) else {
            throw CheckFailure(description: "Cannot construct a keyboard event")
        }
        window.sendEvent(event); settle()
    }
    static func sample() throws -> NeoSnapshot {
        var header = Data(repeating: 0, count: NeoApplet.headerSize)
        header.replaceSubrange(0..<4, with: [0xc0, 0xff, 0xee, 0xad])
        header[20] = 0xa0; header[21] = 0; header[60] = 3; header[61] = 3
        let name = Data("AlphaWord Plus UK".utf8)
        header.replaceSubrange(24..<(24 + name.count), with: name)
        var applet = try NeoApplet(header: header)
        let id = UUID()
        applet.limits = try NeoFileLimits(minimum: 512, maximum: 51_200)
        applet.files = try (0..<8).map { index in
            NeoFile(id: NeoFileID(connection: id, applet: applet.id, index: UInt8(index + 1)),
                    attributes: try NeoFileAttributes(name: "File \(index + 1)", fileSpace: index + 1), size: 512 + index * 1024)
        }
        return NeoSnapshot(connection: id, registryID: 1, systemVersion: "3.6", availableRAM: 378_880, availableROM: 1_048_576, applets: [applet])
    }
    static func main() {
        do { try run() }
        catch {
            FileHandle.standardError.write(Data("Interface check failed: \(error)\n".utf8))
            exit(EXIT_FAILURE)
        }
    }
    static func run() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular); app.finishLaunching(); app.activate(ignoringOtherApps: true)
        let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "build/interface-checks", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let domain = "AlphaSync-InterfaceChecks-" + UUID().uuidString
        guard let defaults = UserDefaults(suiteName: domain) else { throw CheckFailure(description: "Missing test preferences") }
        defer { defaults.removePersistentDomain(forName: domain) }
        let preferences = Preferences(defaults: defaults)
        let store = AppStore(preferences: preferences, monitoringEnabled: false)
        let snapshot = try sample()
        store.devices = [snapshot]; store.sidebar = .device(snapshot.connection)
        store.selection = [snapshot.applets[0].files[0].id]
        try require(store.canImport && store.importApplet?.id == NeoApplet.alphaWord, "A selected file must retain its applet as an import destination")
        store.sidebar = .applet(snapshot.connection, 0x9999); store.reconcileSelection()
        try require(store.chosenApplet?.id == NeoApplet.alphaWord, "An absent applet must not leave a stale selection")
        try require(FileSize.exact(1) == "1 byte", "A single byte must have singular wording")
        for (label, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            app.appearance = NSAppearance(named: appearance)
            store.devices = []; store.sidebar = nil; store.selection = []
            let disconnected = window(MainView(store: store), size: NSSize(width: 360, height: 230), title: "AlphaSync")
            try capture(disconnected, "waiting-" + label, to: output); disconnected.close()
            store.devices = [snapshot]; store.reconcileSelection()
            let connected = window(MainView(store: store), size: NSSize(width: 820, height: 560), title: "AlphaSync")
            try require(connected.contentView!.bounds.width >= 760, "Connected window is too narrow")
            try capture(connected, "files-" + label, to: output); connected.close()
            let about = window(AboutView(), size: NSSize(width: 420, height: 570), title: "About AlphaSync")
            if let button = about.firstResponder as? NSButton {
                try require(!["Project", "Release notes", "Licence"].contains(button.title), "An About link received initial focus")
            }
            try capture(about, "about-" + label, to: output); about.close()
            let settings = window(SettingsView(preferences: preferences), size: NSSize(width: 560, height: 610), title: "Settings")
            try capture(settings, "settings-" + label, to: output); settings.close()
            let inspector = window(InspectorView(store: store), size: NSSize(width: 400, height: 560), title: "Inspector")
            try capture(inspector, "inspector-" + label, to: output); inspector.close()
            for action in ["Clear File", "Replace"] {
                var cancelled = 0, destructive = 0
                let prompt = DestructiveConfirmation(title: action + "?", action: action,
                    explanation: "The selected contents on your Neo will be changed. This cannot be undone.",
                    names: ["File 1"], saveRecovery: true,
                    cancel: { cancelled += 1 }, confirm: { _ in destructive += 1 })
                let warning = window(prompt, size: NSSize(width: 430, height: 240), title: action)
                try capture(warning, action.lowercased().replacingOccurrences(of: " ", with: "-") + "-" + label, to: output)
                try key("\r", code: 36, in: warning)
                try require(cancelled == 1 && destructive == 0, "Return must cancel \(action)")
                try key(" ", code: 49, in: warning)
                try require(destructive == 0, "Space triggered \(action)")
                warning.close()
            }
            let text = "A read-only preview\n\nAlphaSmart Neo text stays selectable.\n" + String(repeating: "More text for scrolling and Find.\n", count: 20)
            let reader = window(ReadOnlyText(text: text), size: NSSize(width: 660, height: 500), title: "File 1")
            guard let view = reader.contentView.flatMap({ descendants($0).first { $0 is NSTextView } }) as? NSTextView else {
                throw CheckFailure(description: "Missing native read-only text view")
            }
            try require(!view.isEditable && view.isSelectable && view.usesFindBar, "Preview must be read-only, selectable, and support Find")
            try require(view.string == text && view.font == .systemFont(ofSize: NSFont.systemFontSize), "Preview changed text or system font")
            view.setSelectedRange(NSRange(location: 2, length: 10))
            let privateClipboard = NSPasteboard.withUniqueName()
            defer { privateClipboard.releaseGlobally() }
            try require(privateClipboard.setString(view.string, forType: .string) && privateClipboard.string(forType: .string) == text, "Clipboard text differs from the full preview")
            try capture(reader, "reader-" + label, to: output); reader.close()
        }
        print("Native interface checks passed. No USB devices or login registrations were changed.")
    }
}
