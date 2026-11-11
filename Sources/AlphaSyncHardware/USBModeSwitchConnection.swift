import Foundation
import IOKit
import IOUSBHost
import AlphaSyncCore

/// Device-level control endpoint access only. This never opens a HID input stream or captures a driver.
final class USBModeSwitchConnection: ModeSwitchConnection {
    private let device: IOUSBHostDevice
    private var closed = false

    init(service: io_service_t) throws {
        device = try IOUSBHostDevice(__ioService: service, options: [], queue: nil, interestHandler: nil)
    }

    func firstConfiguration() throws -> UInt8 {
        guard !closed else { throw NeoError.disconnected }
        return try device.configurationDescriptor(with: 0).pointee.bConfigurationValue
    }

    func configure(_ value: UInt8) throws {
        guard !closed else { throw NeoError.disconnected }
        try device.__configure(withValue: Int(value), matchInterfaces: true)
    }

    func send(_ request: ModeSwitchRequest, timeout: TimeInterval) throws -> Int {
        guard !closed else { throw NeoError.disconnected }
        guard let length = UInt16(exactly: request.data.count), timeout.isFinite, timeout > 0 else {
            throw NeoError.invalidData("Invalid USB mode-switch request bounds.")
        }
        let setup = IOUSBDeviceRequest(bmRequestType: request.requestType, bRequest: request.request,
                                       wValue: request.value.littleEndian, wIndex: request.index.littleEndian,
                                       wLength: length.littleEndian)
        let buffer = try device.ioData(withCapacity: request.data.count)
        buffer.length = request.data.count
        request.data.withUnsafeBytes { bytes in
            if let base = bytes.baseAddress {
                buffer.replaceBytes(in: NSRange(location: 0, length: bytes.count), withBytes: base)
            }
        }
        var count = 0
        try device.__send(setup, data: buffer, bytesTransferred: &count, completionTimeout: timeout)
        return count
    }

    func close() {
        guard !closed else { return }
        closed = true
        device.destroy()
    }

    deinit { if !closed { device.destroy() } }
}
