import Foundation

/// A normalised value buffer. No unaligned loads, raw pointer arithmetic, or unchecked slices.
public struct BinaryReader: Sendable {
    public let bytes: [UInt8]

    public init(_ data: Data) { bytes = Array(data) }

    public func integer(at offset: Int, width: Int) throws -> UInt32 {
        guard (1...4).contains(width), offset >= 0, offset <= bytes.count,
              width <= bytes.count - offset else {
            throw NeoError.invalidData("A numeric field is truncated.")
        }
        return bytes[offset..<(offset + width)].reduce(0) { ($0 << 8) | UInt32($1) }
    }

    public func data(at offset: Int, count: Int) throws -> Data {
        guard offset >= 0, count >= 0, offset <= bytes.count, count <= bytes.count - offset else {
            throw NeoError.invalidData("A data field is truncated.")
        }
        return Data(bytes[offset..<(offset + count)])
    }

    public func string(at offset: Int, count: Int) throws -> String {
        let data = try data(at: offset, count: count)
        let value = data.prefix { $0 != 0 }
        guard let result = String(data: Data(value), encoding: .windowsCP1252) else {
            throw NeoError.invalidData("A name is not valid text.")
        }
        return result
    }
}

extension Data {
    mutating func appendBigEndian(_ value: UInt32, width: Int) {
        for shift in stride(from: (width - 1) * 8, through: 0, by: -8) {
            append(UInt8(truncatingIfNeeded: value >> shift))
        }
    }
}
