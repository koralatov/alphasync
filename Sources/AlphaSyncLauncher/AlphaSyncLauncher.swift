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
    private var launchTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private var launchState = NeoLaunchState()
    func applicationDidFinishLaunching(_ notification: Notification) {
        monitor = Task {
            while !Task.isCancelled {
                // ServiceManagement owns the helper’s lifetime. A delayed preference write must not stop a newly registered helper.
                // Only registry metadata is read here. All USB ownership remains in the main app.
                if let attached = try? NeoPresence.attachedIDs() {
                    launchState.observe(attached)
                    attemptLaunch()
                }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }
    private func attemptLaunch() {
        retryTask?.cancel(); retryTask = nil
        let running = !NSRunningApplication.runningApplications(withBundleIdentifier: "com.tsoniq.AlphaSync").isEmpty
        let now = ContinuousClock.now
        guard let attempt = launchState.beginAttempt(appIsRunning: running, now: now) else {
            if let delay = launchState.retryDelay(from: now) {
                retryTask = Task { [weak self] in
                    do { try await Task.sleep(for: delay) } catch { return }
                    guard !Task.isCancelled else { return }
                    self?.attemptLaunch()
                }
            }
            return
        }
        launchTask = Task {
            var containingApp = Bundle.main.bundleURL
            for _ in 0..<4 { containingApp.deleteLastPathComponent() }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            let succeeded: Bool
            do { _ = try await NSWorkspace.shared.openApplication(at: containingApp, configuration: configuration); succeeded = true }
            catch { NSLog("AlphaSync could not be opened: %@", error.localizedDescription); succeeded = false }
            guard !Task.isCancelled else { return }
            launchState.finish(attempt, succeeded: succeeded, now: .now)
            launchTask = nil
            attemptLaunch()
        }
    }
    func applicationWillTerminate(_ notification: Notification) {
        monitor?.cancel(); retryTask?.cancel(); launchTask?.cancel()
    }
}
