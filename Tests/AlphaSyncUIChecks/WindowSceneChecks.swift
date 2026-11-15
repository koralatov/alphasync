import SwiftUI
import AppKit
@testable import AlphaSyncUI
import AlphaSyncCore

/// Exercise the same scene policy as AlphaSyncApp, without USB discovery or real login items.
@MainActor
struct WindowSceneChecksApp: App {
    @StateObject private var driver = WindowSceneDriver()
    @NSApplicationDelegateAdaptor(WindowSceneLaunchDelegate.self) private var launch

    init() {
        InterfaceChecks.checkpoint("Starting real SwiftUI window scene")
        let output = Self.outputDirectory
        try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try? String(ProcessInfo.processInfo.processIdentifier)
            .write(to: output.appendingPathComponent("process-id"), atomically: true, encoding: .utf8)
    }

    static var outputDirectory: URL {
        let prefix = "--output-directory="
        let argument = CommandLine.arguments.first { $0.hasPrefix(prefix) }
        let path = argument.map { String($0.dropFirst(prefix.count)) } ?? "build/interface-checks/window-scene"
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    var body: some Scene {
        Group {
            Window("AlphaSync", id: "main") {
                MainView(store: driver.store)
                    .environment(\.sidebarRowSize, driver.sidebarSize)
                    .background(WindowSceneProbe { driver.start(in: $0) })
                    .background(FindSceneLauncher(driver: driver))
            }
            .defaultSize(width: 360, height: 230)
            .windowResizability(.contentSize)
            Window("Find fixture", id: "find-fixture") {
                VStack {
                    FindFocusControl().frame(width: 260, height: 26).padding(8)
                    ReadOnlyText(text: "Find this file text.\nA second line for native Find.", findContext: driver.findContext)
                }
                .frame(minWidth: 440, minHeight: 240)
                .focusedSceneValue(\.readerFind, driver.findContext)
                .background(WindowSceneProbe { driver.registerFindWindow($0) })
            }
            .defaultSize(width: 660, height: 320)
        }
        .commands { AlphaSyncCommands(store: driver.store) }
    }
}

@MainActor
private struct FindSceneLauncher: View {
    let driver: WindowSceneDriver
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Color.clear.frame(width: 0, height: 0).onAppear { driver.setOpenWindow(openWindow) }
    }
}

private struct FindFocusControl: NSViewRepresentable {
    func makeNSView(context: Context) -> NSTextField { NSTextField(string: "Unrelated field with keyboard focus") }
    func updateNSView(_ view: NSTextField, context: Context) {}
}

@MainActor
private final class WindowSceneLaunchDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        NSApplication.shared.windows.first?.makeKeyAndOrderFront(nil)
        InterfaceChecks.checkpoint("Window-scene application launched with \(NSApplication.shared.windows.count) windows")
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
    @Published var sidebarSize = SidebarRowSize.medium
    private let preferences: Preferences
    private let defaults: UserDefaults
    private let domain: String
    private let output: URL
    private var started = false
    private var toolbarChecks: [[String: Any]] = []
    private var sidebarChecks: [[String: Any]] = []
    private var findChecks: [[String: Any]] = []
    private var openWindow: OpenWindowAction?
    private weak var findWindow: NSWindow?
    let findContext = ReaderFindContext()

    func setOpenWindow(_ action: OpenWindowAction) { openWindow = action }
    func registerFindWindow(_ window: NSWindow) { findWindow = window }

    init() {
        let domain = "AlphaSync-WindowSceneChecks-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: domain)!
        let preferences = Preferences(defaults: defaults, loginItem: InterfaceLoginItem())
        self.domain = domain; self.defaults = defaults; self.preferences = preferences
        store = AppStore(preferences: preferences, monitoringEnabled: false)
        output = WindowSceneChecksApp.outputDirectory
        InterfaceChecks.checkpoint("Window-scene driver initialised")
    }

    func start(in window: NSWindow) {
        guard !started else { return }
        started = true
        InterfaceChecks.checkpoint("Window-scene probe attached")
        Task {
            do {
                try await run(in: window)
                await store.shutdown()
                let result: [String: Any] = ["passed": true, "layouts": InterfaceChecks.browserLayouts.count]
                try JSONSerialization.data(withJSONObject: result)
                    .write(to: output.appendingPathComponent("result.json"), options: .atomic)
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
        try JSONSerialization.data(withJSONObject: toolbarChecks, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("toolbar-checks.json"), options: .atomic)
        try JSONSerialization.data(withJSONObject: sidebarChecks, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("sidebar-checks.json"), options: .atomic)
        try JSONSerialization.data(withJSONObject: findChecks, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("find-command-checks.json"), options: .atomic)
    }

    private func checkFind(in mainWindow: NSWindow, appearance: String) async throws {
        func items(_ menu: NSMenu) -> [NSMenuItem] {
            menu.update()
            return menu.items + menu.items.compactMap(\.submenu).flatMap(items)
        }
        func check(_ enabled: Bool, stage: String) throws {
            let titles: Set<String> = ["Find…", "Find Next", "Find Previous", "Use Selection for Find"]
            let commands = NSApplication.shared.mainMenu.map(items)?.filter { titles.contains($0.title) } ?? []
            InterfaceChecks.checkpoint("Find availability during \(stage): key \(NSApplication.shared.keyWindow?.title ?? "none"), items \(commands.map { "\($0.title)=\($0.isEnabled)" })")
            try InterfaceChecks.require(commands.count == 4, "The Find menu lost its four commands")
            try InterfaceChecks.require(commands.allSatisfy { $0.isEnabled == enabled }, "Find commands have the wrong availability during " + stage)
            findChecks.append(["appearance": appearance, "stage": stage, "enabled": enabled, "commands": commands.map(\.title)])
        }
        mainWindow.makeKeyAndOrderFront(nil)
        await InterfaceChecks.yieldLayout()
        try check(false, stage: "browser")
        guard let openWindow else { throw CheckFailure(description: "Missing native scene opener") }
        openWindow(id: "find-fixture")
        for _ in 0..<20 {
            if findWindow?.isVisible == true { break }
            await InterfaceChecks.yieldLayout()
        }
        guard let reader = findWindow, let content = reader.contentView, let text = findContext.textView,
              let field = InterfaceChecks.descendants(content).compactMap({ $0 as? NSTextField }).first else {
            throw CheckFailure(description: "The native Find fixture did not open")
        }
        reader.makeKeyAndOrderFront(nil)
        try InterfaceChecks.require(reader.makeFirstResponder(field), "The unrelated field could not receive keyboard focus")
        await InterfaceChecks.yieldLayout()
        try check(true, stage: "reader")
        guard let command = NSApplication.shared.mainMenu.map(items)?.first(where: { $0.title == "Find…" }), let menu = command.menu else {
            throw CheckFailure(description: "Missing enabled Find command")
        }
        menu.performActionForItem(at: menu.index(of: command))
        await InterfaceChecks.yieldLayout()
        try InterfaceChecks.require(text.enclosingScrollView?.isFindBarVisible == true, "Find did not open the native Find bar")
        try capture(reader, "find-reader-" + appearance)
        reader.close()
        mainWindow.makeKeyAndOrderFront(nil)
        await InterfaceChecks.yieldLayout()
        try check(false, stage: "reader-closed")
    }

    private func checkSidebar(in window: NSWindow, appearance: String) async throws {
        guard let content = window.contentView,
              let controller = InterfaceChecks.descendants(content).compactMap({ $0 as? NSSplitView })
                .compactMap({ $0.delegate as? DeviceBrowserController }).first else {
            try InterfaceChecks.require(false, "The connected browser lost its native split controller")
            return
        }
        func menuItems(_ menu: NSMenu) -> [NSMenuItem] {
            menu.items + menu.items.compactMap(\.submenu).flatMap(menuItems)
        }
        let items = NSApplication.shared.mainMenu.map(menuItems) ?? []
        let toggle = #selector(NSSplitViewController.toggleSidebar(_:))
        try InterfaceChecks.require(!items.contains { $0.action == toggle || ["Hide Sidebar", "Show Sidebar", "Toggle Sidebar"].contains($0.title) },
                                    "A menu still lets the sidebar be hidden")
        try InterfaceChecks.require(!(window.toolbar?.items.contains { $0.label.localizedCaseInsensitiveContains("sidebar") } ?? true),
                                    "The toolbar still contains a sidebar control")
        try InterfaceChecks.require(controller.splitViewItems.count == 2 && controller.splitViewItems.allSatisfy { !$0.canCollapse && !$0.isCollapsed },
                                    "A browser pane can still collapse")
        for index in 0..<2 {
            InterfaceChecks.checkpoint("Exercising the former sidebar action \(index + 1) in " + appearance)
            try InterfaceChecks.require(NSApplication.shared.sendAction(toggle, to: controller, from: nil), "The sidebar action did not reach the native controller")
            await InterfaceChecks.yieldLayout()
            try InterfaceChecks.require(controller.splitViewItems.allSatisfy { !$0.isCollapsed }, "The former sidebar action hid a pane")
        }
        for width in [180.0, 300.0, 220.0] {
            controller.splitView.setPosition(width, ofDividerAt: 0)
            await InterfaceChecks.yieldLayout()
            let actual = controller.sidebarHost.view.frame.width
            try InterfaceChecks.require(abs(actual - width) < 2, "The sidebar width did not follow the divider: \(width), actual \(actual)")
            try await InterfaceChecks.checkBrowser(in: window, stage: "sidebar-width-\(Int(width))-" + appearance)
            sidebarChecks.append(["appearance": appearance, "kind": "width", "requested": width, "actual": actual, "canCollapse": false])
        }
        for (name, size) in [("small", SidebarRowSize.small), ("medium", .medium), ("large", .large)] {
            sidebarSize = size
            await InterfaceChecks.yieldLayout()
            try await InterfaceChecks.checkBrowser(in: window, stage: "sidebar-size-" + name + "-" + appearance)
            try capture(window, "sidebar-" + name + "-" + appearance)
            sidebarChecks.append(["appearance": appearance, "kind": "size", "value": name, "width": controller.sidebarHost.view.frame.width])
        }
        sidebarSize = .medium
        await InterfaceChecks.yieldLayout()
    }

    private func checkToolbar(in window: NSWindow, appearance: String) async throws {
        guard let toolbar = window.toolbar else {
            try InterfaceChecks.require(false, "Missing toolbar while checking display modes")
            return
        }
        let expected: Set<String> = ["Back Up", "Clear Files", "Inspector", "Refresh"]
        let labels = toolbar.items.map(\.label)
        InterfaceChecks.checkpoint("Toolbar labels: \(labels)")
        try InterfaceChecks.require(expected.isSubset(of: Set(labels)), "The native toolbar lost a command label")
        for choice in ToolbarAppearance.allCases {
            preferences.toolbarAppearance = choice
            await InterfaceChecks.yieldLayout()
            try InterfaceChecks.require(toolbar.displayMode == choice.displayMode, "The toolbar ignored \(choice.title)")
            let visible = Set((toolbar.visibleItems ?? []).map(\.label))
            try InterfaceChecks.require(expected.isSubset(of: visible), "A command overflowed at minimum width in \(choice.title)")
            try capture(window, "toolbar-" + choice.rawValue + "-" + appearance)
            toolbarChecks.append(["appearance": appearance, "mode": choice.rawValue, "labels": labels, "visible": visible.sorted()])
        }
        toolbar.displayMode = .iconOnly
        await InterfaceChecks.yieldLayout()
        try InterfaceChecks.require(preferences.toolbarAppearance == .iconOnly && defaults.string(forKey: "ToolbarAppearance") == ToolbarAppearance.iconOnly.rawValue,
                                    "A native display-mode change was not saved")
        preferences.toolbarAppearance = .iconAndText
        await InterfaceChecks.yieldLayout()
        let table = try InterfaceChecks.fileTable(in: window)
        if let content = window.contentView, let sidebar = InterfaceChecks.descendants(content).compactMap({ $0 as? NSTableView }).first(where: { $0 !== table && $0.numberOfRows >= 3 }) {
            let first = sidebar.rect(ofRow: 0).height == 0 ? 1 : 0
            try InterfaceChecks.require(sidebar.rect(ofRow: first).height > 0 && abs(sidebar.rect(ofRow: first).height - sidebar.rect(ofRow: first + 1).height) < 1,
                                        "The Neo heading is still smaller than its child rows")
        } else { try InterfaceChecks.require(false, "Missing sidebar while checking the Neo heading") }
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
            InterfaceChecks.checkpoint("Connected toolbar labels: \(window.toolbar?.items.map(\.label) ?? [])")
            let initial = try await InterfaceChecks.checkBrowser(in: window, stage: "connected-" + label)
            store.connectionIssue = "A second Neo could not be opened. Close other Neo software and choose Try Again."
            await InterfaceChecks.yieldLayout()
            let warned = try await InterfaceChecks.checkBrowser(in: window, stage: "connection-warning-" + label)
            try InterfaceChecks.require(warned.maxY < initial.maxY - 12,
                                        "The warning overlaps the first file: before \(initial), after \(warned)")
            try capture(window, "connection-warning-" + label)
            await resize(window, width: 760, height: 460)
            try await InterfaceChecks.checkBrowser(in: window, stage: "minimum-warning-" + label)
            try capture(window, "files-minimum-" + label)
            try await checkToolbar(in: window, appearance: label)
            try await checkSidebar(in: window, appearance: label)
            await resize(window, width: 1120, height: 720)
            try await InterfaceChecks.checkBrowser(in: window, stage: "expanded-warning-" + label)
            store.connectionIssue = nil
            await InterfaceChecks.yieldLayout()
            await resize(window, width: 820, height: 560)
            try await InterfaceChecks.checkBrowser(in: window, stage: "warning-cleared-" + label)
            try capture(window, "files-" + label)
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
            try InterfaceChecks.require(window.toolbar?.displayMode == .iconAndLabel && preferences.toolbarAppearance == .iconAndText,
                                        "Reconnection lost the saved toolbar appearance")
            try capture(window, "reconnected-" + label)
            try await checkFind(in: window, appearance: label)
        }
        try InterfaceChecks.require(InterfaceChecks.browserLayouts.count == 32, "Missing window-scene layout observations")
        try saveGeometry()
    }
}
