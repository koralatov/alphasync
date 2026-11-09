import Foundation

/// A small thread-safe cancellation flag shared with the serial device executor.
public final class StopRequest: @unchecked Sendable {
    private let lock = NSLock()
    private var requested = false

    public init() {}

    public func stop() {
        lock.lock()
        defer { lock.unlock() }
        requested = true
    }

    public var isRequested: Bool {
        lock.lock()
        defer { lock.unlock() }
        return requested
    }
}
