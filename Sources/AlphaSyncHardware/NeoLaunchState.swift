import Foundation

/// Successful launches consume an attachment. Failures have a short, bounded retry window.
public struct NeoLaunchState: Sendable {
    public struct Attempt: Sendable {
        let id: UUID
        let attachments: Set<UInt64>
    }
    private var attached = Set<UInt64>()
    private var handled = Set<UInt64>()
    private var pending = Set<UInt64>()
    private var inFlight: Attempt?
    private var attempts = 0
    private var retryAt: ContinuousClock.Instant?

    public init() {}

    public mutating func observe(_ current: Set<UInt64>) {
        let added = current.subtracting(attached)
        attached = current
        handled.formIntersection(current)
        pending.formIntersection(current)
        pending.formUnion(added.subtracting(handled))
        if !added.isEmpty || pending.isEmpty { attempts = 0; retryAt = nil }
    }

    public mutating func beginAttempt(appIsRunning: Bool, now: ContinuousClock.Instant) -> Attempt? {
        if appIsRunning {
            handled.formUnion(attached)
            pending.removeAll()
            attempts = 0; retryAt = nil
            return nil
        }
        guard inFlight == nil, !pending.isEmpty, attempts < 3, retryAt.map({ $0 <= now }) ?? true else { return nil }
        let attempt = Attempt(id: UUID(), attachments: pending)
        inFlight = attempt
        attempts += 1
        return attempt
    }

    public mutating func finish(_ attempt: Attempt, succeeded: Bool, now: ContinuousClock.Instant) {
        guard inFlight?.id == attempt.id else { return }
        inFlight = nil
        if succeeded {
            handled.formUnion(attempt.attachments.intersection(attached))
            pending.subtract(attempt.attachments)
            attempts = 0; retryAt = pending.isEmpty ? nil : now
        } else if !pending.isEmpty && attempts < 3 {
            retryAt = now.advanced(by: .seconds(attempts == 1 ? 1 : 2))
        } else { retryAt = nil }
    }

    public func retryDelay(from now: ContinuousClock.Instant) -> Duration? {
        guard inFlight == nil, !pending.isEmpty, attempts < 3, let retryAt else { return nil }
        return max(.zero, now.duration(to: retryAt))
    }
}
