import SwiftUI
import AppKit

@MainActor
final class ReaderFindContext: ObservableObject {
    private(set) weak var textView: NSTextView?
    func attach(_ view: NSTextView) { textView = view }
    func perform(_ action: NSFindPanelAction) {
        guard let textView, textView.window?.isKeyWindow == true else { return }
        AppActions.find(action, target: textView)
    }
}

private struct ReaderFindKey: FocusedValueKey { typealias Value = ReaderFindContext }

extension FocusedValues {
    var readerFind: ReaderFindContext? {
        get { self[ReaderFindKey.self] }
        set { self[ReaderFindKey.self] = newValue }
    }
}
