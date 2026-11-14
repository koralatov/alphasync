import Foundation
import IOKit
import IOUSBHost
import AlphaSyncCore

/// A single endpoint request. The native adapter and fault-injection tests use the same packet path.
protocol USBPipeIO: AnyObject {
    func transfer(_ buffer: NSMutableData, timeout: TimeInterval) throws -> Int
    func clearStall() throws
    func abort() throws
}

private final class NativeUSBPipe: USBPipeIO {
    private let pipe: IOUSBHostPipe
    init(_ pipe: IOUSBHostPipe) { self.pipe = pipe }

    func transfer(_ buffer: NSMutableData, timeout: TimeInterval) throws -> Int {
        var count = 0
        try pipe.__sendIORequest(with: buffer, bytesTransferred: &count, completionTimeout: timeout)
        return count
    }
    func clearStall() throws { try pipe.clearStall() }
    func abort() throws { try pipe.__abort(with: .synchronous) }
}

/// All access, including close, belongs to DeviceService’s serial executor.
final class USBHostTransport: NeoTransport {
    private let input: any USBPipeIO
    private let output: any USBPipeIO
    private let releaseInterface: () -> Void
    private var closed = false

    convenience init(service: io_service_t) throws {
        // NS_REFINED_FOR_SWIFT imports these public SDK selectors with a double underscore.
        let host = try IOUSBHostInterface(__ioService: service, options: [], queue: nil, interestHandler: nil)
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
            let input = try NativeUSBPipe(host.copyPipe(withAddress: inputAddress))
            let output = try NativeUSBPipe(host.copyPipe(withAddress: outputAddress))
            self.init(input: input, output: output, releaseInterface: { host.destroy() })
        } catch {
            host.destroy()
            throw error
        }
    }

    init(input: any USBPipeIO, output: any USBPipeIO, releaseInterface: @escaping () -> Void) {
        self.input = input; self.output = output; self.releaseInterface = releaseInterface
    }

    func read(maximum: Int, timeout: TimeInterval) throws -> Data {
        guard !closed else { throw NeoError.disconnected }
        guard (1...8).contains(maximum), timeout.isFinite, timeout > 0 else { throw NeoError.invalidData("Invalid USB read bounds.") }
        do {
            return try USBTransferBuffers.read(maximum: maximum) { buffer in
                try input.transfer(buffer, timeout: timeout)
            }
        } catch {
            try? input.clearStall()
            throw error
        }
    }

    func write(_ data: Data, timeout: TimeInterval) throws {
        guard !closed else { throw NeoError.disconnected }
        let bytes = Array(data)
        let deadline = try TransferDeadline(timeout: timeout)
        var offset = 0
        while offset < bytes.count {
            let length = min(8, bytes.count - offset)
            let remaining = try deadline.remaining()
            let block = Data(bytes[offset..<(offset + length)])
            do {
                try USBTransferBuffers.write(block) { buffer in
                    try output.transfer(buffer, timeout: remaining)
                }
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
        releaseInterface()
    }
    deinit { close() }
}
