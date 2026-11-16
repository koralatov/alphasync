import SwiftUI
import AppKit

@MainActor
final class ReaderFindContext: ObservableObject {
    private(set) weak var textView: NSTextView?
    func attach(_ view: NSTextView) {
        textView = view
        ReaderFindRegistry.shared.register(self)
    }
    func detach(_ view: NSTextView) {
        // An old view can finish dismantling after its replacement has already attached.
        guard textView === view else { return }
        textView = nil
        ReaderFindRegistry.shared.register(self)
    }
    func perform(_ action: NSFindPanelAction) {
        guard let textView, textView.window?.isKeyWindow == true else { return }
        AppActions.find(action, target: textView)
    }
}

/// Associate our own text views with native windows; no framework view traversal is needed.
@MainActor
final class ReaderFindRegistry: ObservableObject {
    static let shared = ReaderFindRegistry()
    @Published private(set) var active: ReaderFindContext?
    private struct Entry { weak var context: ReaderFindContext? }
    private var entries: [Entry] = []
    private var scheduled = false

    private init() {
        // These observers share the process-lifetime registry and do not retain it.
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification, NSWindow.willCloseNotification] {
            _ = NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleUpdate() }
            }
        }
    }

    func register(_ context: ReaderFindContext) {
        entries.removeAll { $0.context == nil }
        if !entries.contains(where: { $0.context === context }) { entries.append(Entry(context: context)) }
        scheduleUpdate()
    }

    private func scheduleUpdate() {
        guard !scheduled else { return }
        scheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            scheduled = false
            entries.removeAll { $0.context == nil }
            let key = NSApplication.shared.keyWindow
            let context = key.flatMap { window in
                window.isVisible ? entries.compactMap(\.context).first { $0.textView?.window === window } : nil
            }
            if active !== context { active = context }
        }
    }
}
