import Foundation
import IOKit
import AlphaSyncCore

struct USBInterface {
    let registryID: UInt64
    let service: io_service_t
}

private struct USBKeyboardDevice {
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
                                                kCFAllocatorDefault, options) as? NSNumber)?.intValue
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

    /// Discover the USB device itself, including Neos without an enumerated HID report interface.
    private static func keyboardDevices() throws -> [USBKeyboardDevice] {
        guard let matching = IOServiceMatching("IOUSBHostDevice") else {
            throw NeoError.device("macOS could not prepare Neo USB discovery. Choose Try Again.")
        }
        var iterator: io_iterator_t = 0
        let status = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
        guard status == KERN_SUCCESS else {
            throw NeoError.device("macOS could not list connected USB devices (\(status)). Choose Try Again.")
        }
        defer { IOObjectRelease(iterator) }
        var result: [USBKeyboardDevice] = []
        while true {
            let service = IOIteratorNext(iterator)
            guard service != 0 else { break }
            if property(service, "idVendor") == vendor, property(service, "idProduct") == keyboardProduct {
                var id: UInt64 = 0
                if IORegistryEntryGetRegistryEntryID(service, &id) == KERN_SUCCESS {
                    result.append(USBKeyboardDevice(registryID: id, service: service))
                    continue
                }
            }
            IOObjectRelease(service)
        }
        return result
    }

    /// Send only the Neo’s mode-switch controls. No keyboard input is requested or observed.
    static func enterTransferMode(state: inout ModeSwitchState, retryFailures: Bool) -> String? {
        let devices: [USBKeyboardDevice]
        do { devices = try keyboardDevices() }
        catch { return [error.localizedDescription, state.issue].compactMap { $0 }.joined(separator: "\n\n") }
        defer { for device in devices { IOObjectRelease(device.service) } }
        state.retainAttached(Set(devices.map(\.registryID)))
        for device in devices.sorted(by: { $0.registryID < $1.registryID }) {
            let id = device.registryID
            guard state.shouldAttempt(id, retryFailures: retryFailures) else { continue }
            do {
                try NeoModeSwitch.perform(USBModeSwitchConnection(service: device.service))
                state.recordSuccess(id)
            } catch {
                let error = error as NSError
                state.recordFailure(id, message: "The Neo could not switch from keyboard mode to file-transfer mode. " +
                    "Close other Neo software and choose Try Again, or reconnect it.\n\n" +
                    "\(error.localizedDescription) (\(error.domain), \(error.code))")
            }
        }
        return state.issue
    }
}
