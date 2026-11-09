import Foundation

/// Keep failed mode switches visible until an explicit retry or disconnection.
struct ModeSwitchState {
    private var completed = Set<UInt64>()
    private var failures: [UInt64: String] = [:]

    mutating func retainAttached(_ attached: Set<UInt64>) {
        completed.formIntersection(attached)
        failures = failures.filter { attached.contains($0.key) }
    }

    func shouldAttempt(_ id: UInt64, retryFailures: Bool) -> Bool {
        !completed.contains(id) && (retryFailures || failures[id] == nil)
    }

    mutating func recordSuccess(_ id: UInt64) {
        completed.insert(id)
        failures.removeValue(forKey: id)
    }

    mutating func recordFailure(_ id: UInt64, message: String) {
        completed.remove(id)
        failures[id] = message
    }

    var issue: String? {
        let messages = failures.keys.sorted().compactMap { failures[$0] }
        return messages.isEmpty ? nil : messages.joined(separator: "\n\n")
    }
}
