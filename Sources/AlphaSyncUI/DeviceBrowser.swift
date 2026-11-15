import AppKit
import SwiftUI

/// A native, resizable browser whose two panes remain visible.
struct DeviceBrowser<Sidebar: View, Detail: View>: NSViewControllerRepresentable {
    let sidebar: Sidebar
    let detail: Detail

    init(@ViewBuilder sidebar: () -> Sidebar, @ViewBuilder detail: () -> Detail) {
        self.sidebar = sidebar()
        self.detail = detail()
    }

    private func pane<Content: View>(_ content: Content, context: Context) -> AnyView {
        AnyView(content
            .environment(\.self, context.environment)
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity))
    }

    func makeNSViewController(context: Context) -> DeviceBrowserController {
        DeviceBrowserController(sidebar: pane(sidebar, context: context), detail: pane(detail, context: context))
    }

    func updateNSViewController(_ controller: DeviceBrowserController, context: Context) {
        controller.sidebarHost.rootView = pane(sidebar, context: context)
        controller.detailHost.rootView = pane(detail, context: context)
    }
}

@MainActor
final class DeviceBrowserController: NSSplitViewController {
    let sidebarHost: NSHostingController<AnyView>
    let detailHost: NSHostingController<AnyView>
    private var positioned = false

    init(sidebar: AnyView, detail: AnyView) {
        sidebarHost = NSHostingController(rootView: sidebar)
        detailHost = NSHostingController(rootView: detail)
        super.init(nibName: nil, bundle: nil)
        // The split items own pane widths; the window owns the browser’s minimum size.
        sidebarHost.sizingOptions = []
        detailHost.sizingOptions = []
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        let navigation = NSSplitViewItem(viewController: sidebarHost)
        navigation.canCollapse = false
        navigation.minimumThickness = 180
        navigation.maximumThickness = 300
        navigation.holdingPriority = .defaultHigh
        let files = NSSplitViewItem(viewController: detailHost)
        files.canCollapse = false
        files.minimumThickness = 400
        addSplitViewItem(navigation)
        addSplitViewItem(files)
    }

    required init?(coder: NSCoder) { return nil }

    override func viewDidAppear() {
        super.viewDidAppear()
        if !positioned {
            positioned = true
            splitView.setPosition(220, ofDividerAt: 0)
        }
    }
}
