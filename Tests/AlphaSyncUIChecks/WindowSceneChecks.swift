import SwiftUI
import AppKit
@testable import AlphaSyncUI
import AlphaSyncCore

/// Exercise the same scene policy as AlphaSyncApp, without USB discovery or real login items.
@MainActor
struct WindowSceneChecksApp: App {
    @StateObject private var driver = WindowSceneDriver()

    var body: some Scene {
        Window("AlphaSync", id: "main") {
            MainView(store: driver.store)
                .background(WindowSceneProbe { driver.start(in: $0) })
        }
        .defaultSize(width: 360, height: 230)
        .windowResizability(.contentSize)
        .commands { AlphaSyncCommands(store: driver.store) }
    }
}

@MainActor
private struct WindowSceneProbe: NSViewRepresentable {
    let ready: @MainActor (NSWindow) -> Void
    func makeNSView(context: Context) -> Probe { Probe(ready: ready) }
    func updateNSView(_ view: Probe, context: Context) {}

    final class Probe: NSView {
        private let ready: @MainActor (NSWindow) -> Void
        private var delivered = false
        init(ready: @escaping @MainActor (NSWindow) -> Void) {
            self.ready = ready
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { return nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard !delivered, let window else { return }
            delivered = true
            ready(window)
        }
    }
}

@MainActor
private final class WindowSceneDriver: ObservableObject {
    let store: AppStore
    private let preferences: Preferences
    private let defaults: UserDefaults
    private let domain: String
    private let output: URL
    private var started = false

    init() {
        let domain = "AlphaSync-WindowSceneChecks-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: domain)!
        let preferences = Preferences(defaults: defaults, loginItem: InterfaceLoginItem())
        self.domain = domain; self.defaults = defaults; self.preferences = preferences
        store = AppStore(preferences: preferences, monitoringEnabled: false)
        output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "build/interface-checks/window-scene", isDirectory: true)
        NSApplication.shared.setActivationPolicy(.regular)
    }

    func start(in window: NSWindow) {
        guard !started else { return }
        started = true
        Task {
            do {
                try await run(in: window)
                await store.shutdown()
                defaults.removePersistentDomain(forName: domain)
                print("SwiftUI window-scene checks passed: \(InterfaceChecks.browserLayouts.count) browser layouts.")
                exit(EXIT_SUCCESS)
            } catch {
                _ = try? InterfaceChecks.capture(window, "failure", to: output, includingTitlebar: true)
                try? saveGeometry()
                if let content = window.contentView {
                    let header = "Window content: \(content.frame); bounds: \(content.bounds); layout: \(window.contentLayoutRect)\n"
                    let views = InterfaceChecks.descendants(content).map {
                        "\(type(of: $0)): frame \($0.frame); bounds \($0.bounds); safe \($0.safeAreaInsets)"
                    }.joined(separator: "\n")
                    try? (header + views).write(to: output.appendingPathComponent("view-tree.txt"), atomically: true, encoding: .utf8)
                }
                defaults.removePersistentDomain(forName: domain)
                FileHandle.standardError.write(Data("Window-scene check failed: \(error)\n".utf8))
                exit(EXIT_FAILURE)
            }
        }
    }

    private func capture(_ window: NSWindow, _ name: String) throws {
        _ = try InterfaceChecks.capture(window, name, to: output, includingTitlebar: true)
    }

    private func resize(_ window: NSWindow, width: CGFloat, height: CGFloat) async {
        InterfaceChecks.resize(window, visibleSize: NSSize(width: width, height: height))
        await InterfaceChecks.yieldLayout()
    }

    private func saveGeometry() throws {
        try JSONSerialization.data(withJSONObject: InterfaceChecks.browserLayouts, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("browser-layout.json"), options: .atomic)
    }

    private func run(in window: NSWindow) async throws {
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        await InterfaceChecks.yieldLayout()
        let snapshot = try InterfaceChecks.sample()
        for (label, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            NSApplication.shared.appearance = NSAppearance(named: appearance)
            preferences.filter = .textApplets
            store.devices = []; store.sidebar = nil; store.selection = []
            await resize(window, width: 360, height: 230)
            try capture(window, "waiting-" + label)
            store.devices = [snapshot]; store.reconcileSelection()
            await InterfaceChecks.yieldLayout()
            await resize(window, width: 820, height: 560)
            try InterfaceChecks.require(window.toolbar != nil && !(window.toolbar?.items.isEmpty ?? true),
                                        "The real SwiftUI scene did not install the app toolbar")
            let initial = try await InterfaceChecks.checkBrowser(in: window, stage: "connected-" + label)
            try capture(window, "files-" + label)
            store.connectionIssue = "A second Neo could not be opened. Close other Neo software and choose Try Again."
            await InterfaceChecks.yieldLayout()
            try capture(window, "connection-warning-" + label)
            let warned = try await InterfaceChecks.checkBrowser(in: window, stage: "connection-warning-" + label)
            try InterfaceChecks.require(warned.maxY < initial.maxY - 12,
                                        "The warning overlaps the first file: before \(initial), after \(warned)")
            await resize(window, width: 760, height: 460)
            try await InterfaceChecks.checkBrowser(in: window, stage: "minimum-warning-" + label)
            try capture(window, "files-minimum-" + label)
            await resize(window, width: 1120, height: 720)
            try await InterfaceChecks.checkBrowser(in: window, stage: "expanded-warning-" + label)
            store.connectionIssue = nil
            await InterfaceChecks.yieldLayout()
            try await InterfaceChecks.checkBrowser(in: window, stage: "warning-cleared-" + label)
            let manyFiles = try InterfaceChecks.sample(fileCount: 64)
            store.devices = [manyFiles]; store.reconcileSelection()
            await resize(window, width: 760, height: 460)
            try await InterfaceChecks.checkBrowser(in: window, stage: "many-files-top-" + label, rows: 64)
            try await InterfaceChecks.checkLastFile(in: window, stage: "many-files-bottom-" + label)
            try capture(window, "files-scrolled-" + label)
            preferences.filter = .allApplets
            await InterfaceChecks.yieldLayout()
            store.sidebar = .applet(manyFiles.connection, 0xb000)
            await InterfaceChecks.yieldLayout()
            try InterfaceChecks.require(!store.canClear && !store.canImport, "A read-only applet enabled file changes")
            try await InterfaceChecks.checkBrowser(in: window, stage: "empty-read-only-applet-" + label, rows: 0)
            try capture(window, "empty-applet-" + label)
            preferences.filter = .alphaWord
            await InterfaceChecks.yieldLayout()
            try InterfaceChecks.require(store.chosenApplet?.id == NeoApplet.alphaWord,
                                        "A hidden applet remained selected after changing the filter")
            try await InterfaceChecks.checkBrowser(in: window, stage: "filtered-applets-" + label, rows: 64)
            store.devices = []; store.reconcileSelection()
            await resize(window, width: 360, height: 230)
            store.devices = [snapshot]; store.reconcileSelection()
            await InterfaceChecks.yieldLayout()
            await resize(window, width: 760, height: 460)
            try await InterfaceChecks.checkBrowser(in: window, stage: "reconnected-" + label)
            try capture(window, "reconnected-" + label)
        }
        try InterfaceChecks.require(InterfaceChecks.browserLayouts.count == 20, "Missing window-scene layout observations")
        try saveGeometry()
    }
}
