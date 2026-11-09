import Foundation
import IOKit
import AlphaSyncCore

public struct DiscoveryResult: Sendable {
    public let devices: [NeoSnapshot]
    public let issue: String?
}

/// The only unchecked boundary: every mutable field and all USB handles are confined to queue.
/// The main actor receives immutable Sendable snapshots and never a driver or registry pointer.
public final class DeviceService: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.koralatov.alphasync.usb", qos: .userInitiated)
    private struct Connection {
        let generation: UUID
        let engine: NeoProtocol
        var snapshot: NeoSnapshot
    }
    private var connections: [UInt64: Connection] = [:]
    private var modeSwitchState = ModeSwitchState()
    private var stopping = false

    public init() {}

    public func perform<T: Sendable>(_ operation: @escaping @Sendable (IsolatedDeviceAccess) throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                guard !stopping else { continuation.resume(throwing: NeoError.disconnected); return }
                do { continuation.resume(returning: try operation(IsolatedDeviceAccess(service: self))) }
                catch { continuation.resume(throwing: error) }
            }
        }
    }

    public func scan() async throws -> DiscoveryResult {
        try await perform { access in try access.scan() }
    }
    public func refresh() async throws -> DiscoveryResult {
        try await perform { access in try access.scan(refresh: true) }
    }
    public func read(_ file: NeoFileID) async throws -> Data {
        try await perform { access in try access.engine(for: file.connection).readFile(applet: file.applet, index: file.index) }
    }
    public func shutdown() async {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                stopping = true
                for item in connections.values { item.engine.close() }
                connections.removeAll()
                continuation.resume()
            }
        }
    }

    /// Created only inside queue.async. Do not retain it or pass it to another executor.
    public final class IsolatedDeviceAccess {
        private unowned let service: DeviceService
        fileprivate init(service: DeviceService) { self.service = service }
        public func engine(for generation: UUID) throws -> NeoProtocol {
            dispatchPrecondition(condition: .onQueue(service.queue))
            guard let connection = service.connections.values.first(where: { $0.generation == generation }) else { throw NeoError.disconnected }
            return connection.engine
        }
        public func snapshot(for generation: UUID) throws -> NeoSnapshot {
            dispatchPrecondition(condition: .onQueue(service.queue))
            guard let connection = service.connections.values.first(where: { $0.generation == generation }) else { throw NeoError.disconnected }
            return connection.snapshot
        }
        public func update(_ generation: UUID) throws -> NeoSnapshot {
            dispatchPrecondition(condition: .onQueue(service.queue))
            guard let key = service.connections.first(where: { $0.value.generation == generation })?.key,
                  var connection = service.connections[key] else { throw NeoError.disconnected }
            let value = try connection.engine.snapshot(connection: generation, registryID: key)
            connection.snapshot = value
            service.connections[key] = connection
            return value
        }
        fileprivate func scan(refresh: Bool = false) throws -> DiscoveryResult {
            dispatchPrecondition(condition: .onQueue(service.queue))
            let found = try USBDiscovery.interfaces()
            defer { for interface in found { IOObjectRelease(interface.service) } }
            let attached = Set(found.map(\.registryID))
            for key in Array(service.connections.keys) where !attached.contains(key) {
                service.connections.removeValue(forKey: key)?.engine.close()
            }
            var issue: String?
            for item in found {
                if let connection = service.connections[item.registryID] {
                    if refresh {
                        do { _ = try update(connection.generation) }
                        catch {
                            service.connections.removeValue(forKey: item.registryID)?.engine.close()
                            issue = error.localizedDescription
                        }
                    }
                    continue
                }
                var opened: NeoProtocol?
                do {
                    let transport = try USBHostTransport(service: item.service)
                    let engine = NeoProtocol(transport: transport); opened = engine
                    let generation = UUID()
                    let snapshot = try engine.snapshot(connection: generation, registryID: item.registryID)
                    service.connections[item.registryID] = Connection(generation: generation, engine: engine, snapshot: snapshot)
                } catch {
                    opened?.close()
                    issue = "The Neo could not be opened. \(error.localizedDescription)"
                }
            }
            USBDiscovery.enterTransferMode(state: &service.modeSwitchState, retryFailures: refresh)
            if let modeIssue = service.modeSwitchState.issue { issue = modeIssue }
            return DiscoveryResult(devices: service.connections.values.map(\.snapshot).sorted { $0.registryID < $1.registryID }, issue: issue)
        }
    }
}
