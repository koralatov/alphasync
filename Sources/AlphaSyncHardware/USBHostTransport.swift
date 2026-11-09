import Foundation
import IOKit
import IOUSBHost
import AlphaSyncCore

/// All access, including close, belongs to DeviceService’s serial executor.
final class USBHostTransport: NeoTransport {
    private let interface: IOUSBHostInterface
    private let input: IOUSBHostPipe
    private let output: IOUSBHostPipe
    private var closed = false

    init(service: io_service_t) throws {
        let host = try IOUSBHostInterface(ioService: service, options: [], queue: nil, interestHandler: nil)
        do {
            let configuration = host.configurationDescriptor
            let descriptor = host.interfaceDescriptor
            var current: UnsafePointer<IOUSBDescriptorHeader>?
            var inputAddress: Int?, outputAddress: Int?
            var count = 0
            while let endpoint = IOUSBGetNextEndpointDescriptor(configuration, descriptor, current) {
                count += 1
                guard count <= 32 else { throw NeoError.invalidData("The USB endpoint list did not terminate.") }
                let value = endpoint.pointee
                if value.bmAttributes & 3 == 2 {
                    let address = Int(value.bEndpointAddress)
                    if address & 0x80 != 0 { inputAddress = inputAddress ?? address }
                    else { outputAddress = outputAddress ?? address }
                }
                current = UnsafeRawPointer(endpoint).assumingMemoryBound(to: IOUSBDescriptorHeader.self)
            }
            guard let inputAddress, let outputAddress else {
                throw NeoError.device("The Neo’s file-transfer interface has no bulk input and output pipes.")
            }
            input = try host.copyPipe(withAddress: inputAddress)
            output = try host.copyPipe(withAddress: outputAddress)
            interface = host
        } catch {
            host.destroy()
            throw error
        }
    }

    func read(maximum: Int, timeout: TimeInterval) throws -> Data {
        guard !closed else { throw NeoError.disconnected }
        guard (1...8).contains(maximum), timeout > 0 else { throw NeoError.invalidData("Invalid USB read bounds.") }
        let buffer = try interface.ioData(withCapacity: maximum)
        buffer.length = maximum
        do {
            let count = try input.sendIORequest(with: buffer, completionTimeout: timeout)
            guard count >= 0, count <= maximum else { throw NeoError.invalidData("The USB read count is invalid.") }
            return Data((buffer as Data).prefix(count))
        } catch {
            try? input.clearStall()
            throw error
        }
    }

    func write(_ data: Data, timeout: TimeInterval) throws {
        guard !closed else { throw NeoError.disconnected }
        let bytes = Array(data)
        let deadline = Date().addingTimeInterval(timeout)
        var offset = 0
        while offset < bytes.count {
            let length = min(8, bytes.count - offset)
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { throw NeoError.device("The Neo did not accept its command in time.") }
            let buffer = try interface.ioData(withCapacity: length)
            buffer.length = length
            let block = Array(bytes[offset..<(offset + length)])
            block.withUnsafeBytes { raw in
                if let base = raw.baseAddress { buffer.replaceBytes(in: NSRange(location: 0, length: length), withBytes: base) }
            }
            do {
                let count = try output.sendIORequest(with: buffer, completionTimeout: remaining)
                guard count == length else { throw NeoError.device("The Neo accepted only part of a command.") }
            } catch {
                try? output.clearStall()
                throw error
            }
            offset += length
        }
    }

    func close() {
        guard !closed else { return }
        closed = true
        try? input.abort()
        try? output.abort()
        interface.destroy()
    }
    deinit { interface.destroy() }
}
