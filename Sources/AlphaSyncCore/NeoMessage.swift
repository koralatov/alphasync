// Eight-byte framing derived from tSoniq’s BSD-licensed ASMessage.h. See LICENSE.
import Foundation

public struct NeoMessage: Equatable, Sendable {
    private var bytes: [UInt8]
    public var command: UInt8 { bytes[0] }
    public var data: Data { Data(bytes) }

    public init(command: UInt8) { bytes = [command, 0, 0, 0, 0, 0, 0, command] }
    public init(data: Data) throws {
        let bytes = Array(data)
        guard bytes.count == 8, bytes.prefix(7).reduce(UInt8(0), &+) == bytes[7] else {
            throw NeoError.invalidData("A command reply has the wrong length or checksum.")
        }
        self.bytes = bytes
    }
    public func argument(at offset: Int, width: Int) throws -> UInt32 {
        guard offset >= 1, width >= 1, width <= 4, offset <= 6, width <= 7 - offset else {
            throw NeoError.invalidData("A command field is out of bounds.")
        }
        return try BinaryReader(data).integer(at: offset, width: width)
    }
    public mutating func set(_ value: UInt32, at offset: Int, width: Int) throws {
        _ = try argument(at: offset, width: width)
        guard width == 4 || value < (UInt32(1) << (width * 8)) else {
            throw NeoError.invalidData("A command value would be truncated.")
        }
        for index in 0..<width {
            bytes[offset + index] = UInt8(truncatingIfNeeded: value >> ((width - index - 1) * 8))
        }
        bytes[7] = bytes.prefix(7).reduce(UInt8(0), &+)
    }
}

public struct NeoSetting: Equatable, Sendable {
    public let type: UInt16
    public let id: UInt16
    public let value: Data
}

public enum NeoSettings {
    public static func decode(_ data: Data) throws -> [NeoSetting] {
        guard data.count <= 8192 else { throw NeoError.invalidData("The settings reply is too large.") }
        let reader = BinaryReader(data)
        var offset = 0, result: [NeoSetting] = []
        while offset < data.count {
            // All-zero trailing bytes are the documented end marker or alignment padding.
            if reader.bytes[offset...].allSatisfy({ $0 == 0 }) { break }
            guard data.count - offset >= 6 else { throw NeoError.invalidData("A settings header is truncated.") }
            let type = UInt16(try reader.integer(at: offset, width: 2))
            let id = UInt16(try reader.integer(at: offset + 2, width: 2))
            let size = Int(try reader.integer(at: offset + 4, width: 2))
            let padded = size + (size & 1)
            guard padded <= data.count - offset - 6 else { throw NeoError.invalidData("A settings value is truncated.") }
            result.append(NeoSetting(type: type, id: id, value: try reader.data(at: offset + 6, count: size)))
            offset += 6 + padded
        }
        return result
    }

    public static func alphaWordLimits(_ data: Data) throws -> NeoFileLimits {
        let items = try decode(data)
        let maximums = items.filter { $0.type == 0x0102 && $0.id == 0x1010 }
        let minimums = items.filter { $0.type == 0x0102 && $0.id == 0x1011 }
        guard maximums.count == 1, minimums.count <= 1 else { throw NeoError.limitsUnavailable }
        let maximum = Int(try BinaryReader(maximums[0].value).integer(at: 0, width: 4))
        let minimum = try minimums.first.map { Int(try BinaryReader($0.value).integer(at: 0, width: 4)) } ?? 0
        return try NeoFileLimits(minimum: max(256, minimum), maximum: min(maximum, 0xffffff))
    }
}
