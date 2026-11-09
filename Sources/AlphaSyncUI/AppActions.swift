import AppKit

@MainActor
public enum AppActions {
    public static func help() { NSHelpManager.shared.openHelpAnchor("alphasync-home", inBook: "AlphaSync Help") }
    public static func licence() { NSHelpManager.shared.openHelpAnchor("alphasync-licence", inBook: "AlphaSync Help") }
    public static func openFolder(_ url: URL) {
        if !NSWorkspace.shared.open(url) {
            let alert = NSAlert()
            alert.messageText = "The folder could not be opened"
            alert.informativeText = "The folder may not exist yet. Recovery copies are created when you first replace or clear a file.\n\n\(url.path)"
            alert.addButton(withTitle: "OK")
            if let window = NSApp.keyWindow { alert.beginSheetModal(for: window) } else { alert.runModal() }
        }
    }
    public static func open(_ url: URL) {
        if !NSWorkspace.shared.open(url) {
            let alert = NSAlert()
            alert.messageText = "The link could not be opened"
            alert.informativeText = "Check your default browser or mail app. You can also copy this link:\n\n\(url.absoluteString)"
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "Copy Link")
            if alert.runModal() == .alertSecondButtonReturn {
                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(url.absoluteString, forType: .string)
            }
        }
    }
    public static func find(_ action: NSFindPanelAction) {
        let sender = NSMenuItem(title: "Find", action: nil, keyEquivalent: "")
        sender.tag = action.rawValue
        NSApp.sendAction(#selector(NSTextView.performFindPanelAction(_:)), to: nil, from: sender)
    }
}
