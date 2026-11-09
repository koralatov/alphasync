import AppKit
import AlphaSyncHardware

@main
@MainActor
enum AlphaSyncLauncher {
    static func main() {
        let app = NSApplication.shared
        let delegate = LaunchDelegate()
        app.delegate = delegate
        app.run()
        withExtendedLifetime(delegate) {}
    }
}

@MainActor
private final class LaunchDelegate: NSObject, NSApplicationDelegate {
    private var monitor: Task<Void, Never>?
    private let defaults = UserDefaults(suiteName: "com.tsoniq.AlphaSync")
    func applicationDidFinishLaunching(_ notification: Notification) {
        monitor = Task {
            var seen = Set<UInt64>()
            while !Task.isCancelled {
                guard defaults?.bool(forKey: "AutoRun") == true else { NSApp.terminate(nil); return }
                // Only registry metadata is read here. All USB ownership remains in the main app.
                if let attached = try? NeoPresence.attachedIDs() {
                    let added = attached.subtracting(seen)
                    seen = attached
                    if !added.isEmpty, NSRunningApplication.runningApplications(withBundleIdentifier: "com.tsoniq.AlphaSync").isEmpty {
                        var containingApp = Bundle.main.bundleURL
                        for _ in 0..<4 { containingApp.deleteLastPathComponent() }
                        let configuration = NSWorkspace.OpenConfiguration()
                        configuration.activates = true
                        do { _ = try await NSWorkspace.shared.openApplication(at: containingApp, configuration: configuration) }
                        catch { NSLog("AlphaSync could not be opened: %@", error.localizedDescription) }
                    }
                }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }
    func applicationWillTerminate(_ notification: Notification) { monitor?.cancel() }
}
