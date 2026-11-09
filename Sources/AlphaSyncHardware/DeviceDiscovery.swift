import Foundation
import IOKit
import AlphaSyncCore

/// Instances and their connections stay on DeviceService’s serial executor.
protocol DeviceDiscovery: AnyObject {
    func devices() throws -> [any DeviceAttachment]
    func modeSwitchIssue(retryFailures: Bool) -> String?
}

protocol DeviceAttachment: AnyObject {
    var registryID: UInt64 { get }
    func open() throws -> any DeviceConnection
}

protocol DeviceConnection: AnyObject {
    func close()
    func snapshot(connection: UUID, registryID: UInt64) throws -> NeoSnapshot
    func fileLimits(applet: UInt16) throws -> NeoFileLimits
    func availableMemory() throws -> (ram: Int, rom: Int)
    func attributes(applet: UInt16, index: UInt8) throws -> NeoFileAttributes
    func readFile(applet: UInt16, index: UInt8, checkingCancellation: () throws -> Void) throws -> Data
    func writeFile(_ data: Data, applet: UInt16, index: UInt8, expectedOriginal: Data) throws
    func createFile(_ data: Data, name: String, applet: UInt16) throws -> UInt8
    func rename(applet: UInt16, index: UInt8, to name: String) throws
}

extension DeviceConnection {
    func readFile(applet: UInt16, index: UInt8) throws -> Data {
        try readFile(applet: applet, index: index, checkingCancellation: {})
    }
}

extension NeoProtocol: DeviceConnection {}

final class SystemDeviceDiscovery: DeviceDiscovery {
    private var modeSwitchState = ModeSwitchState()

    func devices() throws -> [any DeviceAttachment] {
        try USBDiscovery.interfaces().map { SystemDeviceAttachment($0) }
    }

    func modeSwitchIssue(retryFailures: Bool) -> String? {
        USBDiscovery.enterTransferMode(state: &modeSwitchState, retryFailures: retryFailures)
        return modeSwitchState.issue
    }
}

private final class SystemDeviceAttachment: DeviceAttachment {
    let registryID: UInt64
    private let service: io_service_t

    init(_ interface: USBInterface) {
        registryID = interface.registryID
        service = interface.service
    }

    deinit { IOObjectRelease(service) }

    func open() throws -> any DeviceConnection {
        NeoProtocol(transport: try USBHostTransport(service: service))
    }
}
