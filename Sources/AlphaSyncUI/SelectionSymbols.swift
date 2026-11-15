import AlphaSyncCore

/// Use the same familiar symbols wherever a Neo, applet, or file is shown.
enum SelectionSymbols {
    static let device = "externaldrive.connected.to.line.below"
    static let file = "doc.text"
    static func applet(_ id: UInt16) -> String {
        switch id {
        case NeoApplet.alphaWord: return "square.and.pencil"
        case NeoApplet.dictionary: return "text.book.closed"
        case 0: return "gearshape"
        default: return "app"
        }
    }
}
