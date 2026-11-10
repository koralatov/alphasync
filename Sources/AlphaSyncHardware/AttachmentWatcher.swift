import Foundation
import AlphaSyncCore

struct MonitorRetryPolicy: Sendable {
    private var failures = 0
    mutating func nextDelay(healthyFor duration: Duration) -> Duration {
        if duration >= .seconds(60) { failures = 0 }
        failures += 1
        switch failures {
        case 1: return .seconds(1)
        case 2: return .seconds(2)
        default: failures = 0; return .seconds(30)
        }
    }
}

/// Healthy observers wait for events. Only a failed observer uses the bounded retry burst and cooldown.
@MainActor
public final class AttachmentWatcher {
    private let factory: @Sendable () -> AttachmentMonitor
    private let sleep: @Sendable (Duration) async throws -> Void
    private let onEvent: @MainActor () throws -> Void
    private let onFailure: @MainActor (Error) -> Void
    private let onRecovery: @MainActor () -> Void
    private var task: Task<Void, Never>?
    private var generation = UUID()

    public init(factory: @escaping @Sendable () -> AttachmentMonitor = { NeoPresence.monitorAttachments() },
                sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task<Never, Never>.sleep(for: $0) },
                onEvent: @escaping @MainActor () throws -> Void,
                onFailure: @escaping @MainActor (Error) -> Void,
                onRecovery: @escaping @MainActor () -> Void = {}) {
        self.factory = factory; self.sleep = sleep
        self.onEvent = onEvent; self.onFailure = onFailure; self.onRecovery = onRecovery
    }
    deinit { task?.cancel() }

    public func start() {
        guard task == nil else { return }
        let id = UUID()
        generation = id
        let factory = factory, sleep = sleep
        let onEvent = onEvent, onFailure = onFailure, onRecovery = onRecovery
        task = Task { [weak self] in
            defer { if self?.generation == id { self?.task = nil } }
            var retry = MonitorRetryPolicy()
            while !Task.isCancelled {
                let began = ContinuousClock.now
                do {
                    let observer = factory()
                    defer { observer.cancel() }
                    for try await _ in observer.events {
                        try Task.checkCancellation()
                        try onEvent()
                        onRecovery()
                    }
                    try Task.checkCancellation()
                    throw NeoError.device("USB attachment monitoring stopped. AlphaSync will try again.")
                } catch {
                    guard !Task.isCancelled else { return }
                    onFailure(error)
                    let delay = retry.nextDelay(healthyFor: began.duration(to: .now))
                    do { try await sleep(delay) } catch { return }
                }
            }
        }
    }
    public func restart() {
        stop()
        start()
    }
    public func stop() {
        generation = UUID()
        task?.cancel()
        task = nil
    }
}
