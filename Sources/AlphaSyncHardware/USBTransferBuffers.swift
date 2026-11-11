import Foundation
import AlphaSyncCore

/// IOUSBHost accepts ordinary NSMutableData. Keep these tiny Neo transfers out of fixed kernel buffers.
enum USBTransferBuffers {
    static func read(maximum: Int, perform: (NSMutableData) throws -> Int) throws -> Data {
        guard (1...Int(UInt16.max)).contains(maximum), let buffer = NSMutableData(length: maximum) else {
            throw NeoError.invalidData("Invalid USB read buffer size.")
        }
        let count = try perform(buffer)
        guard count >= 0, count <= maximum, count <= buffer.length else {
            throw NeoError.invalidData("The USB read count is invalid.")
        }
        return Data(bytes: buffer.mutableBytes, count: count)
    }

    static func write(_ data: Data, perform: (NSMutableData) throws -> Int) throws {
        guard (1...Int(UInt16.max)).contains(data.count) else {
            throw NeoError.invalidData("Invalid USB write buffer size.")
        }
        let buffer = NSMutableData(data: data)
        guard try perform(buffer) == data.count else {
            throw NeoError.device("The Neo accepted only part of a command.")
        }
    }
}
