import Foundation
import IOKit
import AlphaSyncCore

/// Metadata-only discovery for the login helper. This does not open devices, read keys, or change modes.
public enum NeoPresence {
    public static func attachedIDs() throws -> Set<UInt64> {
        guard let matching = IOServiceMatching("IOUSBHostDevice") else { return [] }
        var iterator: io_iterator_t = 0
        let status = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
        guard status == KERN_SUCCESS else { throw NeoError.device("macOS could not list connected USB devices (\(status)).") }
        defer { IOObjectRelease(iterator) }
        var result = Set<UInt64>()
        while true {
            let service = IOIteratorNext(iterator)
            guard service != 0 else { break }
            defer { IOObjectRelease(service) }
            guard USBDiscovery.property(service, "idVendor") == USBDiscovery.vendor,
                  let product = USBDiscovery.property(service, "idProduct"),
                  [USBDiscovery.keyboardProduct, USBDiscovery.transferProduct].contains(product) else { continue }
            var id: UInt64 = 0
            if IORegistryEntryGetRegistryEntryID(service, &id) == KERN_SUCCESS { result.insert(id) }
        }
        return result
    }
}
