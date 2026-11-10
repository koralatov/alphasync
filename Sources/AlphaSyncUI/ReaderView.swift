import SwiftUI
import AppKit
import AlphaSyncCore

private struct ReaderLoad: Hashable {
    let request: UUID
    let retry: UInt64
}

public struct ReaderView: View {
    @ObservedObject private var store: AppStore
    private let request: ReaderRequest
    @State private var text: String?
    @State private var failure: String?
    @State private var copyFailure = false
    @State private var retry: UInt64 = 0
    @State private var monospaced = UserDefaults.standard.bool(forKey: "FileViewerMonospaced")
    public init(request: ReaderRequest, store: AppStore) { self.request = request; self.store = store }
    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Font:", selection: $monospaced) {
                    Text("Regular").tag(false)
                    Text("Monospaced").tag(true)
                }.pickerStyle(.segmented).frame(width: 270).help("Choose the system regular or monospaced font")
                Spacer()
            }.padding(12)
            Divider()
            if let text {
                ReadOnlyText(text: text, monospaced: monospaced)
            } else if let failure {
                VStack(spacing: 14) {
                    Label("The file could not be read", systemImage: "exclamationmark.triangle").font(.headline)
                    Text(failure).multilineTextAlignment(.center)
                    Button("Try Again") { retry &+= 1 }
                }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView("Reading from Neo…").frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            HStack {
                Label("Read-only", systemImage: "pencil.slash").foregroundStyle(.secondary)
                if text?.isEmpty == true { Text("This file is empty.").foregroundStyle(.secondary) }
                Spacer()
                Button("Copy to Clipboard") {
                    guard let text else { return }
                    NSPasteboard.general.clearContents()
                    if !NSPasteboard.general.setString(text, forType: .string) { copyFailure = true }
                }.disabled(text?.isEmpty ?? true).help("Copy the complete loaded file without changing its selection")
            }.padding(12)
        }
        .frame(minWidth: 440, idealWidth: 660, maxWidth: .infinity, minHeight: 320, idealHeight: 500, maxHeight: .infinity)
        .navigationTitle(request.name)
        .alert("The text could not be copied", isPresented: $copyFailure) {
            Button("OK", role: .cancel) {}
        } message: { Text("Try copying the text again.") }
        .task(id: ReaderLoad(request: request.id, retry: retry)) { await load() }
        .onChange(of: monospaced) { UserDefaults.standard.set($0, forKey: "FileViewerMonospaced") }
    }
    private func load() async {
        text = nil
        failure = nil
        do {
            let result = try await store.readText(request.file)
            guard !Task.isCancelled else { return }
            text = result
        } catch {
            guard !Task.isCancelled else { return }
            failure = error.localizedDescription
        }
    }
}

/// SwiftUI owns the window and controls. This small public-AppKit adapter supplies the macOS 13
/// read-only text selection, responder-chain Copy, and native Find bar that TextEditor cannot provide.
public struct ReadOnlyText: NSViewRepresentable {
    public let text: String
    public let monospaced: Bool
    public init(text: String, monospaced: Bool = false) { self.text = text; self.monospaced = monospaced }
    public func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        let view = NSTextView()
        view.isEditable = false; view.isSelectable = true; view.isRichText = false
        view.usesFindBar = true; view.isIncrementalSearchingEnabled = true
        view.isHorizontallyResizable = false; view.isVerticallyResizable = true
        view.minSize = .zero
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        view.autoresizingMask = [.width]
        view.textContainer?.widthTracksTextView = true
        view.textContainerInset = NSSize(width: 12, height: 12)
        view.textColor = .textColor; view.backgroundColor = .textBackgroundColor
        view.setAccessibilityLabel("Read-only file text")
        scroll.documentView = view
        return scroll
    }
    public func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? NSTextView else { return }
        let ranges = view.selectedRanges, origin = scroll.contentView.bounds.origin
        if view.string != text { view.string = text }
        view.font = monospaced ? .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular) : .systemFont(ofSize: NSFont.systemFontSize)
        let valid = ranges.filter { NSMaxRange($0.rangeValue) <= (text as NSString).length }
        view.selectedRanges = valid.isEmpty ? [NSValue(range: NSRange(location: 0, length: 0))] : valid
        scroll.contentView.scroll(to: origin)
        scroll.reflectScrolledClipView(scroll.contentView)
    }
}
