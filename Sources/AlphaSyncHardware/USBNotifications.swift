import Foundation
import IOKit
import AlphaSyncCore

public final class AttachmentMonitor: Sendable {
    public let events: AsyncThrowingStream<Void, Error>
    private let cancellation: @Sendable () -> Void
    init(events: AsyncThrowingStream<Void, Error>, cancel: @escaping @Sendable () -> Void) {
        self.events = events
        cancellation = cancel
    }
    public func cancel() { cancellation() }
    deinit { cancellation() }
}

/// IOKit ports, iterators, and callback state belong only to this private serial queue.
private final class USBNotifications: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.koralatov.alphasync.attachments")
    private let continuation: AsyncThrowingStream<Void, Error>.Continuation
    private var port: IONotificationPortRef?
    private var iterators: [io_iterator_t] = []
    private var known = Set<UInt64>()
    private var stopped = false

    init(_ continuation: AsyncThrowingStream<Void, Error>.Continuation) { self.continuation = continuation }

    static func monitor() -> AttachmentMonitor {
        let (events, continuation) = AsyncThrowingStream<Void, Error>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let owner = USBNotifications(continuation)
        continuation.onTermination = { [weak owner] _ in owner?.cancel() }
        owner.start()
        return AttachmentMonitor(events: events, cancel: { owner.cancel() })
    }

    private func start() {
        queue.async { [self] in
            guard !stopped else { return }
            guard let created = IONotificationPortCreate(kIOMainPortDefault) else {
                continuation.finish(throwing: NeoError.device("macOS could not create a USB attachment monitor. Choose Try Again."))
                return
            }
            port = created
            IONotificationPortSetDispatchQueue(created, queue)
            for matched in [true, false] {
                guard let matching = IOServiceMatching("IOUSBHostInterface") else {
                    stop()
                    continuation.finish(throwing: NeoError.device("macOS could not prepare USB attachment matching. Choose Try Again."))
                    return
                }
                var iterator: io_iterator_t = 0
                let callback: IOServiceMatchingCallback
                if matched { callback = matchedInterfaces } else { callback = terminatedInterfaces }
                let status = IOServiceAddMatchingNotification(created, matched ? kIOMatchedNotification : kIOTerminatedNotification,
                    matching, callback, Unmanaged.passUnretained(self).toOpaque(), &iterator)
                guard status == KERN_SUCCESS else {
                    if iterator != 0 { IOObjectRelease(iterator) }
                    stop()
                    continuation.finish(throwing: NeoError.device("macOS could not monitor USB attachments (\(status)). Choose Try Again."))
                    return
                }
                iterators.append(iterator)
                drain(iterator, matched: matched)
            }
            // Draining the initial iterators arms notifications and gives every consumer an initial scan.
            continuation.yield(())
        }
    }

    func drain(_ iterator: io_iterator_t, matched: Bool) {
        dispatchPrecondition(condition: .onQueue(queue))
        var changed = false
        while true {
            let service = IOIteratorNext(iterator)
            guard service != 0 else { break }
            defer { IOObjectRelease(service) }
            var id: UInt64 = 0
            let identified = IORegistryEntryGetRegistryEntryID(service, &id) == KERN_SUCCESS
            if matched {
                guard identified, USBDiscovery.property(service, "idVendor") == USBDiscovery.vendor,
                      let product = USBDiscovery.property(service, "idProduct"),
                      [USBDiscovery.keyboardProduct, USBDiscovery.transferProduct].contains(product) else { continue }
                known.insert(id)
                changed = true
            } else if !identified || known.remove(id) != nil { changed = true }
        }
        if changed && !stopped { continuation.yield(()) }
    }

    private func cancel() {
        queue.async {
            self.stop()
            self.continuation.finish()
        }
    }

    private func stop() {
        dispatchPrecondition(condition: .onQueue(queue))
        guard !stopped else { return }
        stopped = true
        if let port {
            IONotificationPortSetDispatchQueue(port, nil)
            IONotificationPortDestroy(port)
            self.port = nil
        }
        for iterator in iterators { IOObjectRelease(iterator) }
        iterators.removeAll()
        known.removeAll()
    }
}

private func matchedInterfaces(_ context: UnsafeMutableRawPointer?, _ iterator: io_iterator_t) {
    guard let context else { return }
    Unmanaged<USBNotifications>.fromOpaque(context).takeUnretainedValue().drain(iterator, matched: true)
}

private func terminatedInterfaces(_ context: UnsafeMutableRawPointer?, _ iterator: io_iterator_t) {
    guard let context else { return }
    Unmanaged<USBNotifications>.fromOpaque(context).takeUnretainedValue().drain(iterator, matched: false)
}

extension NeoPresence {
    /// Metadata-only attachment notifications. Cancel when leaving the event loop, including an early return.
    public static func monitorAttachments() -> AttachmentMonitor { USBNotifications.monitor() }
}
