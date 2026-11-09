import Foundation
import AlphaSyncCore

public struct DiscoveryResult: Sendable {
    public let devices: [NeoSnapshot]
    public let issue: String?
}

/// The USB concurrency boundary: mutable connection state and handles are confined to queue.
/// The main actor receives immutable Sendable snapshots and never a driver or registry pointer.
public final class DeviceService: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.koralatov.alphasync.usb", qos: .userInitiated)
    private struct Connection {
        let generation: UUID
        let engine: any DeviceConnection
        var snapshot: NeoSnapshot
    }
    private var connections: [UInt64: Connection] = [:]
    private var connectionFailures: [UInt64: String] = [:]
    private let discoveryFactory: @Sendable () -> any DeviceDiscovery
    private let eventSource: @Sendable () -> AsyncThrowingStream<Void, Error>
    private var discovery: (any DeviceDiscovery)?
    private var stopping = false

    public convenience init() {
        self.init(discoveryFactory: { SystemDeviceDiscovery() })
    }

    init(discoveryFactory: @escaping @Sendable () -> any DeviceDiscovery,
         eventSource: @escaping @Sendable () -> AsyncThrowingStream<Void, Error> = { NeoPresence.attachmentEvents() }) {
        self.discoveryFactory = discoveryFactory
        self.eventSource = eventSource
    }

    public func attachmentEvents() -> AsyncThrowingStream<Void, Error> { eventSource() }

    func perform<T: Sendable>(_ operation: @escaping @Sendable (IsolatedDeviceAccess) throws -> T) async throws -> T {
        let cancellation = StopRequest()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                queue.async { [self] in
                    guard !stopping else {
                        continuation.resume(throwing: NeoError.disconnected)
                        return
                    }
                    do {
                        let access = IsolatedDeviceAccess(service: self, cancellation: cancellation)
                        try access.checkCancellation()
                        continuation.resume(returning: try operation(access))
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        } onCancel: {
            cancellation.stop()
        }
    }

    public func scan() async throws -> DiscoveryResult {
        try await perform { access in try access.scan() }
    }
    public func refresh(retryConnections: Bool = false) async throws -> DiscoveryResult {
        try await perform { access in try access.scan(refresh: true, retryConnections: retryConnections) }
    }
    public func read(_ file: NeoFileID) async throws -> Data {
        try await perform { access in
            try access.engine(for: file.connection).readFile(applet: file.applet, index: file.index) {
                try access.checkCancellation()
            }
        }
    }
    public func shutdown() async {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                stopping = true
                for item in connections.values {
                    item.engine.close()
                }
                connections.removeAll()
                continuation.resume()
            }
        }
    }

    /// Created only inside queue.async. Do not retain it or pass it to another executor.
    final class IsolatedDeviceAccess {
        private unowned let service: DeviceService
        private let cancellation: StopRequest
        fileprivate init(service: DeviceService, cancellation: StopRequest) {
            self.service = service
            self.cancellation = cancellation
        }
        var isCancellationRequested: Bool {
            dispatchPrecondition(condition: .onQueue(service.queue))
            return cancellation.isRequested
        }
        func checkCancellation() throws {
            if isCancellationRequested { throw CancellationError() }
        }
        func engine(for generation: UUID) throws -> any DeviceConnection {
            dispatchPrecondition(condition: .onQueue(service.queue))
            guard let connection = service.connections.values.first(where: { $0.generation == generation }) else { throw NeoError.disconnected }
            return connection.engine
        }
        func snapshot(for generation: UUID) throws -> NeoSnapshot {
            dispatchPrecondition(condition: .onQueue(service.queue))
            guard let connection = service.connections.values.first(where: { $0.generation == generation }) else { throw NeoError.disconnected }
            return connection.snapshot
        }
        func update(_ generation: UUID) throws -> NeoSnapshot {
            dispatchPrecondition(condition: .onQueue(service.queue))
            guard let key = service.connections.first(where: { $0.value.generation == generation })?.key,
                  var connection = service.connections[key] else { throw NeoError.disconnected }
            let value = try connection.engine.snapshot(connection: generation, registryID: key)
            connection.snapshot = value
            service.connections[key] = connection
            return value
        }
        fileprivate func scan(refresh: Bool = false, retryConnections: Bool = false) throws -> DiscoveryResult {
            dispatchPrecondition(condition: .onQueue(service.queue))
            let discovery = service.discovery ?? service.discoveryFactory()
            service.discovery = discovery
            let found = try discovery.devices()
            let attached = Set(found.map(\.registryID))
            service.connectionFailures = service.connectionFailures.filter { attached.contains($0.key) }
            for key in Array(service.connections.keys) where !attached.contains(key) {
                service.connections.removeValue(forKey: key)?.engine.close()
            }
            for item in found {
                if let connection = service.connections[item.registryID] {
                    if refresh {
                        do { _ = try update(connection.generation) }
                        catch {
                            service.connections.removeValue(forKey: item.registryID)?.engine.close()
                            service.connectionFailures[item.registryID] = error.localizedDescription
                        }
                    }
                    continue
                }
                // A failed connection waits for an explicit retry or physical reconnection.
                if service.connectionFailures[item.registryID] != nil && !retryConnections { continue }
                var opened: (any DeviceConnection)?
                do {
                    let engine = try item.open()
                    opened = engine
                    let generation = UUID()
                    let snapshot = try engine.snapshot(connection: generation, registryID: item.registryID)
                    service.connections[item.registryID] = Connection(generation: generation, engine: engine, snapshot: snapshot)
                    service.connectionFailures.removeValue(forKey: item.registryID)
                } catch {
                    opened?.close()
                    service.connectionFailures[item.registryID] = "The Neo could not be opened. \(error.localizedDescription)"
                }
            }
            var issues = service.connectionFailures.keys.sorted().compactMap { service.connectionFailures[$0] }
            if let modeIssue = discovery.modeSwitchIssue(retryFailures: retryConnections) { issues.append(modeIssue) }
            return DiscoveryResult(devices: service.connections.values.map(\.snapshot).sorted { $0.registryID < $1.registryID },
                                   issue: issues.isEmpty ? nil : issues.joined(separator: "\n\n"))
        }
    }
}
