import Foundation

public enum NeoError: Error, LocalizedError, Equatable, Sendable {
    case invalidData(String)
    case device(String)
    case disconnected
    case cancelled
    case unsupportedCharacter(String)
    case tooLarge(required: Int, maximum: Int)
    case insufficientMemory(required: Int, available: Int)
    case limitsUnavailable
    case verificationFailed

    public var errorDescription: String? {
        switch self {
        case .invalidData(let reason): return "The Neo returned invalid data. \(reason)"
        case .device(let reason): return reason
        case .disconnected: return "The Neo is no longer connected. Reconnect it and try again."
        case .cancelled: return "The operation was cancelled."
        case .unsupportedCharacter(let character):
            return "The Neo cannot represent \(character). Remove or replace this character in your text file, then try again. No device files were changed."
        case .tooLarge(let required, let maximum):
            return "The converted file needs \(required.formatted()) bytes. The Neo’s maximum is \(maximum.formatted()) bytes. Shorten the text or split it into smaller files. No device files were changed."
        case .insufficientMemory(let required, let available):
            return "The converted file needs \(required.formatted()) bytes, but only \(available.formatted()) bytes are available. No device files were changed."
        case .limitsUnavailable: return "AlphaSync could not read the Neo’s file limits. Reconnect your Neo and try again. No device files were changed."
        case .verificationFailed: return "AlphaSync could not verify the changed file. Its contents may already have changed. Check the Neo and your recovery copy before trying again."
        }
    }
}

public struct NeoWriteError: Error, LocalizedError, Sendable {
    public let reason: String
    public init(reason: String) { self.reason = reason }
    public var errorDescription: String? {
        if reason.contains("may already have changed") { return reason }
        return "The Neo could not confirm the change. Device contents may already have changed. " + reason
    }
}
