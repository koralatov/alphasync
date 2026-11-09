import Foundation

/// Transfer timeouts measure elapsed time, independently of wall-clock corrections.
public struct TransferDeadline: Sendable {
    private let start: ContinuousClock.Instant
    private let timeout: TimeInterval

    public init(timeout: TimeInterval, start: ContinuousClock.Instant = .now) throws {
        guard timeout.isFinite, timeout > 0 else {
            throw NeoError.invalidData("A transfer timeout is invalid.")
        }
        self.start = start
        self.timeout = timeout
    }

    public func remaining(at instant: ContinuousClock.Instant = .now) throws -> TimeInterval {
        let elapsed = start.duration(to: instant).components
        let seconds = Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1_000_000_000_000_000_000
        let remaining = timeout - seconds
        guard remaining > 0 else {
            throw NeoError.device("The Neo did not complete its transfer in time.  Reconnect it and try again.")
        }
        return remaining
    }
}
