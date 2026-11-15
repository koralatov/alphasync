import AppKit
import SwiftUI

extension ToolbarAppearance {
    var displayMode: NSToolbar.DisplayMode {
        switch self {
        case .iconAndText: return .iconAndLabel
        case .iconOnly: return .iconOnly
        case .textOnly: return .labelOnly
        }
    }
    init?(displayMode: NSToolbar.DisplayMode) {
        switch displayMode {
        case .iconAndLabel: self = .iconAndText
        case .iconOnly: self = .iconOnly
        case .labelOnly: self = .textOnly
        default: return nil
        }
    }
}

/// Apply the saved display mode to SwiftUI’s own toolbar using public AppKit API.
struct ToolbarAppearanceController: NSViewRepresentable {
    @ObservedObject var preferences: Preferences
    let connected: Bool

    func makeNSView(context: Context) -> ToolbarAppearanceView {
        ToolbarAppearanceView(preferences: preferences)
    }
    func updateNSView(_ view: ToolbarAppearanceView, context: Context) { view.scheduleUpdate() }

    @MainActor
    final class ToolbarAppearanceView: NSView {
        private let preferences: Preferences
        private weak var observedToolbar: NSToolbar?
        private var observation: NSKeyValueObservation?
        private var scheduled = false

        init(preferences: Preferences) {
            self.preferences = preferences
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { return nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observation = nil
            observedToolbar = nil
            scheduleUpdate()
        }

        func scheduleUpdate() {
            guard !scheduled else { return }
            scheduled = true
            // SwiftUI installs its toolbar after attaching the content view.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                scheduled = false
                apply()
            }
        }

        private func apply() {
            guard let toolbar = window?.toolbar else { return }
            if toolbar !== observedToolbar {
                observation = nil
                observedToolbar = toolbar
                toolbar.displayMode = preferences.toolbarAppearance.displayMode
                if #available(macOS 15, *) { toolbar.allowsDisplayModeCustomization = true }
                observation = toolbar.observe(\.displayMode, options: [.new]) { [weak self] _, _ in
                    Task { @MainActor [weak self] in self?.saveDisplayMode() }
                }
            } else if toolbar.displayMode != preferences.toolbarAppearance.displayMode {
                toolbar.displayMode = preferences.toolbarAppearance.displayMode
            }
        }

        private func saveDisplayMode() {
            guard let toolbar = observedToolbar, toolbar === window?.toolbar,
                  let appearance = ToolbarAppearance(displayMode: toolbar.displayMode),
                  appearance != preferences.toolbarAppearance else { return }
            preferences.toolbarAppearance = appearance
        }
    }
}
