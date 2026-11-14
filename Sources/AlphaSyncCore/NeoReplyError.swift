import Foundation

/// Keep rejected commands identifiable without recording file contents or passwords.
struct NeoReplyError: Error, LocalizedError, Equatable, Sendable {
    let request: UInt8
    let reply: UInt8
    let applet: UInt16?

    init(request message: NeoMessage, reply response: NeoMessage) {
        request = message.command
        reply = response.command
        switch request {
        case 0x0c, 0x13, 0x1b, 0x1c, 0x1d, 0x1e, 0x1f:
            applet = (try? message.argument(at: 5, width: 2)).map { UInt16($0) }
        default:
            applet = nil
        }
    }

    var errorDescription: String? {
        let target = applet.map { String(format: " for applet 0x%04X", Int($0)) } ?? ""
        return String(format: "The Neo could not complete request 0x%02X", Int(request)) + target +
            String(format: " (reply 0x%02X). Reconnect it and try again.", Int(reply))
    }
}
