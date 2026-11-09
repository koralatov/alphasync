import SwiftUI
import AppKit
import AlphaSyncUI

@main
@MainActor
struct AlphaSyncApp: App {
    @StateObject private var store = AppStore()
    @NSApplicationDelegateAdaptor(ApplicationDelegate.self) private var delegate

    init() {
        if CommandLine.arguments.contains("--version") {
            print("AlphaSync \(AppMetadata.version) (build \(AppMetadata.build))")
            exit(EXIT_SUCCESS)
        }
    }

    var body: some Scene {
        Window("AlphaSync", id: "main") {
            MainView(store: store).onAppear { delegate.store = store }
        }
        .defaultSize(width: 360, height: 230)
        .windowResizability(.contentSize)
        .commands { AlphaSyncCommands(store: store) }

        WindowGroup(for: ReaderRequest.self) { $request in
            if let request { ReaderView(request: request, store: store) }
        }
        .defaultSize(width: 660, height: 500)

        Window("Inspector", id: "inspector") { InspectorView(store: store) }
            .windowResizability(.contentSize)
        Window("About AlphaSync", id: "about") { AboutView() }
            .windowResizability(.contentSize)
        Settings { SettingsView(preferences: store.preferences) }
    }
}

/// SwiftUI owns all app windows. This delegate lets pending transfers finish safely before quitting.
@MainActor
final class ApplicationDelegate: NSObject, NSApplicationDelegate {
    weak var store: AppStore?
    private var quitting = false
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !quitting else { return .terminateLater }
        quitting = true
        guard let store else { return .terminateNow }
        Task {
            await store.shutdown()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { true }
}
