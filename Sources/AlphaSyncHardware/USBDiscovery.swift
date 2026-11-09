import Foundation
import IOKit
import IOKit.hid
import AlphaSyncCore

struct USBInterface {
    let registryID: UInt64
    let service: io_service_t
}

enum USBDiscovery {
    static let vendor = 0x081e
    static let keyboardProduct = 0xbd04
    static let transferProduct = 0xbd01

    static func property(_ service: io_registry_entry_t, _ name: String) -> Int? {
        let options = IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents)
        return (IORegistryEntrySearchCFProperty(service, kIOServicePlane, name as CFString,
                                                kCFAllocatorDefault, options)?.takeRetainedValue() as? NSNumber)?.intValue
    }

    /// Returned service references are owned and must each be released by the caller.
    static func interfaces() throws -> [USBInterface] {
        guard let matching = IOServiceMatching("IOUSBHostInterface") else { return [] }
        var iterator: io_iterator_t = 0
        let status = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
        guard status == KERN_SUCCESS else { throw NeoError.device("macOS could not list USB interfaces (\(status)).") }
        defer { IOObjectRelease(iterator) }
        var results: [USBInterface] = []
        while true {
            let service = IOIteratorNext(iterator)
            if service == 0 { break }
            if property(service, "idVendor") == vendor, property(service, "idProduct") == transferProduct {
                var registryID: UInt64 = 0
                if IORegistryEntryGetRegistryEntryID(service, &registryID) == KERN_SUCCESS {
                    results.append(USBInterface(registryID: registryID, service: service))
                    continue
                }
            }
            IOObjectRelease(service)
        }
        return results
    }

    /// Only the Neo’s output-report interface is opened. No keyboard input is requested or observed.
    static func enterTransferMode(attempted: inout Set<UInt64>) throws {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(0))
        IOHIDManagerSetDeviceMatching(manager, [kIOHIDVendorIDKey: vendor, kIOHIDProductIDKey: keyboardProduct] as CFDictionary)
        let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> ?? []
        var attached = Set<UInt64>()
        defer { attempted.formIntersection(attached) }
        for device in devices {
            let service = IOHIDDeviceGetService(device)
            guard property(service, "bInterfaceNumber") == 1 else { continue }
            var id: UInt64 = 0
            guard IORegistryEntryGetRegistryEntryID(service, &id) == KERN_SUCCESS else { continue }
            attached.insert(id)
            guard attempted.insert(id).inserted else { continue }
            let opened = IOHIDDeviceOpen(device, IOOptionBits(0))
            guard opened == kIOReturnSuccess else {
                throw NeoError.device("macOS could not open the Neo’s mode-switch interface (\(opened)). Close other Neo software and reconnect it.")
            }
            defer { IOHIDDeviceClose(device, IOOptionBits(0)) }
            for code: UInt8 in 0xe0...0xe4 {
                var report = code
                let status = IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, 0, &report, 1)
                guard status == kIOReturnSuccess else {
                    throw NeoError.device("The Neo could not switch to file-transfer mode (\(status)). Reconnect it and try again.")
                }
            }
        }
    }
}
