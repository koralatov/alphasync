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
    private var watcher: AttachmentWatcher?
    private var launchTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private var launchState = NeoLaunchState()
    func applicationDidFinishLaunching(_ notification: Notification) {
        watcher = AttachmentWatcher(onEvent: { [weak self] in
            guard let self else { return }
            // Only registry metadata is read here. USB ownership remains in the main app.
            self.launchState.observe(try NeoPresence.attachedIDs())
            self.attemptLaunch()
        }, onFailure: { error in NSLog("Neo attachment monitoring failed: %@", error.localizedDescription) })
        watcher?.start()
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(didWake),
                                                          name: NSWorkspace.didWakeNotification, object: nil)
    }
    @objc private func didWake(_ notification: Notification) { watcher?.restart() }
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
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        watcher?.stop(); retryTask?.cancel(); launchTask?.cancel()
    }
}
