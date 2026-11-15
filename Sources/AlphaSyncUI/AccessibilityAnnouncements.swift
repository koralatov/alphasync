import AppKit

/// Coalesce related non-modal status changes without repeating a sheet’s own announcement.
@MainActor
final class AccessibilityAnnouncements {
    private struct Connection: Equatable {
        let count: Int
        let issue: String?
        var message: String {
            let status = count == 0 ? "No Neo connected." : (count == 1 ? "Neo connected." : "\(count.formatted()) Neos connected.")
            return issue.map { status + "  " + $0 } ?? status
        }
    }
    private let post: @MainActor (String) -> Void
    private var connection = Connection(count: 0, issue: nil)
    private var pending: Task<Void, Never>?

    init(post: @escaping @MainActor (String) -> Void = AccessibilityAnnouncements.systemPost) { self.post = post }
    deinit { pending?.cancel() }

    static func systemPost(_ message: String) {
        guard NSWorkspace.shared.isVoiceOverEnabled, NSApplication.shared.isActive else { return }
        NSAccessibility.post(element: NSApplication.shared, notification: .announcementRequested,
            userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.low.rawValue])
    }
    func connectionChanged(count: Int, issue: String?) {
        let next = Connection(count: count, issue: issue)
        guard next != connection else { return }
        connection = next
        pending?.cancel()
        pending = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(200)) }
            catch { return }
            guard !Task.isCancelled, let self else { return }
            pending = nil
            post(next.message)
        }
    }
    func completed(_ message: String) {
        // A pending connection announcement already explains the initial refresh.
        guard pending == nil else { return }
        post(message)
    }
    func cancel() { pending?.cancel(); pending = nil }
}
