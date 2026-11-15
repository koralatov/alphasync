import SwiftUI
import AppKit
import ServiceManagement
@testable import AlphaSyncUI
import AlphaSyncCore

private struct CheckFailure: Error, CustomStringConvertible { let description: String }

@MainActor
private final class InterfaceLoginItem: LoginItemManaging {
    var status: SMAppService.Status { .notRegistered }
    func register() throws { throw CheckFailure(description: "Interface checks must not register a login item") }
    func unregister() throws { throw CheckFailure(description: "Interface checks must not unregister a login item") }
}

/// This executable renders disposable sample data. It never starts USB discovery or registers a login item.
@main
@MainActor
struct InterfaceChecks {
    static var browserLayouts: [[String: Any]] = []
    static func checkpoint(_ message: String) {
        FileHandle.standardOutput.write(Data(("Interface check: " + message + "\n").utf8))
    }
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw CheckFailure(description: message) }
    }
    static func settle() { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.35)) }
    static func descendants(_ root: NSView) -> [NSView] { [root] + root.subviews.flatMap(descendants) }
    static func fileTable(in window: NSWindow) throws -> NSTableView {
        guard let content = window.contentView,
              let table = descendants(content).compactMap({ $0 as? NSTableView }).first(where: { $0.tableColumns.count == 2 }) else {
            throw CheckFailure(description: "Missing native file table")
        }
        return table
    }

    static func frameRecord(_ rect: NSRect) -> [String: CGFloat] {
        ["x": rect.minX, "y": rect.minY, "width": rect.width, "height": rect.height]
    }

    static func resize(_ window: NSWindow, visibleSize: NSSize) {
        let chrome = max(0, (window.contentView?.bounds.height ?? 0) - window.contentLayoutRect.height)
        window.setContentSize(NSSize(width: visibleSize.width, height: visibleSize.height + chrome))
        settle()
    }

    @discardableResult
    static func checkBrowser(in window: NSWindow, stage: String, rows: Int = 8) throws -> NSRect {
        checkpoint("Checking browser layout: " + stage)
        guard let content = window.contentView else { throw CheckFailure(description: "Missing content view") }
        let table = try fileTable(in: window)
        guard let sidebar = descendants(content).compactMap({ $0 as? NSTableView }).first(where: {
            $0 !== table && $0.numberOfRows >= 3 && $0.enclosingScrollView != nil
        }) else { throw CheckFailure(description: "Missing native sidebar") }
        try require(table.numberOfRows == rows, "The file table lost rows during \(stage)")
        if rows > 0 { table.scrollRowToVisible(0) }
        sidebar.scrollRowToVisible(0)
        settle()
        let safe = window.contentLayoutRect
        var record: [String: Any] = ["stage": stage, "contentLayout": frameRecord(safe), "fileRows": rows]
        for (name, list, indices) in [("files", table, rows > 0 ? [0] : []), ("sidebar", sidebar, [0, 1])] {
            guard let scroll = list.enclosingScrollView else { throw CheckFailure(description: "Missing scroll view") }
            let clip = scroll.contentView.convert(scroll.contentView.bounds, to: nil)
            for index in indices {
                let row = list.convert(list.rect(ofRow: index), to: nil)
                try require(row.height > 0 && row.maxY <= min(safe.maxY, clip.maxY) + 1,
                            "The first \(name) item is covered at the top during \(stage): \(row), safe \(safe), clip \(clip)")
                try require(row.minY >= max(safe.minY, clip.minY) - 1,
                            "The first \(name) item is outside its viewport during \(stage)")
                record[name + "Row\(index)"] = frameRecord(row)
            }
        }
        if rows > 0 {
            guard let header = table.headerView, !header.isHidden else { throw CheckFailure(description: "Missing file column headings") }
            let rect = header.convert(header.bounds, to: nil)
            try require(rect.height > 0 && rect.maxY <= safe.maxY + 1,
                        "The file headings are covered by the toolbar during \(stage)")
            record["fileHeadings"] = frameRecord(rect)
        }
        browserLayouts.append(record)
        return rows > 0 ? table.convert(table.rect(ofRow: 0), to: nil) : .zero
    }

    static func checkLastFile(in window: NSWindow, stage: String) throws {
        let table = try fileTable(in: window)
        table.scrollRowToVisible(table.numberOfRows - 1)
        settle()
        guard let scroll = table.enclosingScrollView else { throw CheckFailure(description: "Missing file scroll view") }
        let row = table.convert(table.rect(ofRow: table.numberOfRows - 1), to: nil)
        let clip = scroll.contentView.convert(scroll.contentView.bounds, to: nil)
        let safe = window.contentLayoutRect
        try require(row.minY >= max(safe.minY + 20, clip.minY) - 1 && row.maxY <= min(safe.maxY, clip.maxY) + 1,
                    "The final file cannot scroll clear of the status bar during \(stage)")
        browserLayouts.append(["stage": stage, "lastFile": frameRecord(row), "contentLayout": frameRecord(safe)])
    }

    static func window<V: View>(_ view: V, size: NSSize, title: String, fullSizeToolbar: Bool = false) -> NSWindow {
        checkpoint("Opening " + title)
        let result = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: fullSizeToolbar ? [.titled, .closable, .resizable, .fullSizeContentView] : [.titled, .closable, .resizable],
                              backing: .buffered, defer: false)
        result.isReleasedWhenClosed = false
        result.title = title
        result.contentViewController = NSHostingController(rootView: view)
        if fullSizeToolbar {
            result.toolbarStyle = .unified
            result.toolbar = result.toolbar ?? NSToolbar(identifier: "AlphaSync-InterfaceChecks")
        }
        result.setContentSize(size)
        result.center(); result.makeKeyAndOrderFront(nil)
        settle()
        if fullSizeToolbar {
            resize(result, visibleSize: size)
            checkpoint("Full-size toolbar window ready")
        }
        return result
    }
    @discardableResult
    static func capture(_ window: NSWindow, _ name: String, to output: URL) throws -> Data {
        checkpoint("Capturing " + name)
        guard let view = window.contentView else { throw CheckFailure(description: "Missing content view") }
        view.layoutSubtreeIfNeeded(); view.displayIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw CheckFailure(description: "Cannot capture \(name)") }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        // NSHostingView is transparent. Include the native window colour so standalone PNGs remain readable.
        guard let opaque = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: bitmap.pixelsWide, pixelsHigh: bitmap.pixelsHigh,
                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                    bytesPerRow: 0, bitsPerPixel: 0), let context = NSGraphicsContext(bitmapImageRep: opaque) else {
            throw CheckFailure(description: "Cannot create the capture background")
        }
        opaque.size = bitmap.size
        guard let image = bitmap.cgImage else { throw CheckFailure(description: "Cannot read the captured pixels") }
        window.effectiveAppearance.performAsCurrentDrawingAppearance {
            let canvas = context.cgContext
            let bounds = NSRect(origin: .zero, size: bitmap.size)
            canvas.setBlendMode(.copy)
            canvas.setFillColor(NSColor.windowBackgroundColor.cgColor)
            canvas.fill(bounds)
            canvas.setBlendMode(.normal)
            canvas.draw(image, in: bounds)
        }
        try require((opaque.colorAt(x: 0, y: 0)?.alphaComponent ?? 0) > 0.99, "Capture background must be opaque")
        guard let bytes = opaque.representation(using: .png, properties: [:]) else { throw CheckFailure(description: "Cannot encode \(name)") }
        try bytes.write(to: output.appendingPathComponent(name + ".png"), options: .atomic)
        guard let pixels = opaque.bitmapData else { throw CheckFailure(description: "Missing captured pixels") }
        return Data(bytes: pixels, count: opaque.bytesPerRow * opaque.pixelsHigh)
    }
    static func key(_ character: String, code: UInt16, in window: NSWindow) throws {
        guard let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                          windowNumber: window.windowNumber, context: nil, characters: character,
                                          charactersIgnoringModifiers: character, isARepeat: false, keyCode: code) else {
            throw CheckFailure(description: "Cannot construct a keyboard event")
        }
        window.sendEvent(event); settle()
    }
    static func sample(fileCount: Int = 8) throws -> NeoSnapshot {
        var header = Data(repeating: 0, count: NeoApplet.headerSize)
        header.replaceSubrange(0..<4, with: [0xc0, 0xff, 0xee, 0xad])
        header[20] = 0xa0; header[21] = 0; header[60] = 3; header[61] = 3
        let name = Data("AlphaWord Plus UK".utf8)
        header.replaceSubrange(24..<(24 + name.count), with: name)
        var applet = try NeoApplet(header: header)
        let id = UUID()
        applet.limits = try NeoFileLimits(minimum: 512, maximum: 51_200)
        var files: [NeoFile] = []
        for index in 0..<fileCount {
            let number = index + 1
            let size = 512 + (index % 8) * 1024
            let fileID = NeoFileID(connection: id, applet: applet.id, index: UInt8(number))
            let attributes = try NeoFileAttributes(name: "File \(number)", allocation: size, fileSpace: (index % 8) + 1)
            files.append(NeoFile(id: fileID, attributes: attributes, size: size))
        }
        applet.files = files
        header[20] = 0xb0
        header.replaceSubrange(24..<60, with: Data(repeating: 0, count: 36))
        let readOnlyName = Data("Read-only Applet".utf8)
        header.replaceSubrange(24..<(24 + readOnlyName.count), with: readOnlyName)
        let readOnly = try NeoApplet(header: header)
        return NeoSnapshot(connection: id, registryID: 1, systemVersion: "3.6", availableRAM: 378_880,
                           availableROM: 1_048_576, applets: [applet, readOnly])
    }
    static func main() {
        do { try run() }
        catch {
            let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "build/interface-checks", isDirectory: true)
            for window in NSApplication.shared.windows where window.isVisible {
                try? capture(window, "failure-\(window.windowNumber)", to: output)
            }
            try? JSONSerialization.data(withJSONObject: browserLayouts, options: [.prettyPrinted, .sortedKeys])
                .write(to: output.appendingPathComponent("browser-layout.json"), options: .atomic)
            FileHandle.standardError.write(Data("Interface check failed: \(error)\n".utf8))
            exit(EXIT_FAILURE)
        }
    }
    static func run() throws {
        checkpoint("Starting AppKit")
        let app = NSApplication.shared
        app.setActivationPolicy(.regular); app.finishLaunching(); app.activate(ignoringOtherApps: true)
        checkpoint("AppKit ready")
        let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "build/interface-checks", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let domain = "AlphaSync-InterfaceChecks-" + UUID().uuidString
        guard let defaults = UserDefaults(suiteName: domain) else { throw CheckFailure(description: "Missing test preferences") }
        defer { defaults.removePersistentDomain(forName: domain) }
        let preferences = Preferences(defaults: defaults, loginItem: InterfaceLoginItem())
        checkpoint("Private preferences ready")
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
            preferences.filter = .textApplets
            store.devices = []; store.sidebar = nil; store.selection = []
            let connected = window(MainView(store: store), size: NSSize(width: 360, height: 230),
                                   title: "AlphaSync", fullSizeToolbar: true)
            try capture(connected, "waiting-" + label, to: output)
            store.devices = [snapshot]; store.reconcileSelection()
            settle(); resize(connected, visibleSize: NSSize(width: 820, height: 560))
            try require(connected.contentView!.bounds.width >= 760, "Connected window is too narrow")
            try require(connected.styleMask.contains(.fullSizeContentView) && connected.toolbar != nil &&
                        connected.contentView!.bounds.height > connected.contentLayoutRect.height + 10,
                        "The layout fixture must include content beneath a real title bar and toolbar")
            let initialRow = try checkBrowser(in: connected, stage: "connected-" + label)
            let withoutWarning = try capture(connected, "files-" + label, to: output)
            store.connectionIssue = "A second Neo could not be opened. Close other Neo software and choose Try Again."
            settle()
            let withWarning = try capture(connected, "connection-warning-" + label, to: output)
            try require(withWarning != withoutWarning, "A connected Neo must visibly show its connection warning")
            let warnedRow = try checkBrowser(in: connected, stage: "connection-warning-" + label)
            try require(warnedRow.maxY < initialRow.maxY - 12,
                        "A connection warning must reserve space above the first file: before \(initialRow), after \(warnedRow)")
            resize(connected, visibleSize: NSSize(width: 760, height: 460))
            try checkBrowser(in: connected, stage: "minimum-warning-" + label)
            try capture(connected, "files-minimum-" + label, to: output)
            resize(connected, visibleSize: NSSize(width: 1120, height: 720))
            try checkBrowser(in: connected, stage: "expanded-warning-" + label)
            store.connectionIssue = nil
            settle()
            try checkBrowser(in: connected, stage: "warning-cleared-" + label)
            let manyFiles = try sample(fileCount: 64)
            store.devices = [manyFiles]; store.reconcileSelection()
            resize(connected, visibleSize: NSSize(width: 760, height: 460))
            try checkBrowser(in: connected, stage: "many-files-top-" + label, rows: 64)
            try checkLastFile(in: connected, stage: "many-files-bottom-" + label)
            try capture(connected, "files-scrolled-" + label, to: output)
            preferences.filter = .allApplets
            settle()
            store.sidebar = .applet(manyFiles.connection, 0xb000)
            settle()
            try require(!store.canClear && !store.canImport, "An empty read-only applet must not enable file changes")
            try checkBrowser(in: connected, stage: "empty-read-only-applet-" + label, rows: 0)
            try capture(connected, "empty-applet-" + label, to: output)
            preferences.filter = .alphaWord
            settle()
            try require(store.chosenApplet?.id == NeoApplet.alphaWord, "Changing the filter must replace a hidden applet selection")
            try checkBrowser(in: connected, stage: "filtered-applets-" + label, rows: 64)
            store.devices = []; store.reconcileSelection()
            resize(connected, visibleSize: NSSize(width: 360, height: 230))
            store.devices = [snapshot]; store.reconcileSelection()
            settle(); resize(connected, visibleSize: NSSize(width: 760, height: 460))
            try checkBrowser(in: connected, stage: "reconnected-" + label)
            try capture(connected, "reconnected-" + label, to: output)
            connected.close()
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
        try JSONSerialization.data(withJSONObject: browserLayouts, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("browser-layout.json"), options: .atomic)
        print("Checked \(browserLayouts.count) native browser layouts with full-size toolbars.")
        print("Native interface checks passed. No USB devices or login registrations were changed.")
    }
}
