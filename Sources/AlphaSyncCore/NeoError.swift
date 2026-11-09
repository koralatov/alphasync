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
            return "The Neo cannot represent \(character).  Remove or replace this character in your text file, then try again."
        case .tooLarge(let required, let maximum):
            return "The converted file needs \(required.formatted()) bytes.  The Neo’s maximum is \(maximum.formatted()) bytes.  Shorten the text or split it into smaller files."
        case .insufficientMemory(let required, let available):
            return "The converted file needs \(required.formatted()) bytes, but only \(available.formatted()) bytes are available."
        case .limitsUnavailable: return "AlphaSync could not read the Neo’s file limits.  Reconnect your Neo and try again."
        case .verificationFailed: return "AlphaSync could not verify the changed file."
        }
    }
}

public struct NeoWriteError: Error, LocalizedError, Sendable {
    public let underlying: any Error
    public init(underlying: any Error) { self.underlying = underlying }
    public var errorDescription: String? {
        "The Neo could not confirm the change.  Device contents may already have changed.  " + underlying.localizedDescription
    }
}
