// AlphaWord escaping and wrapping derived from tSoniq’s BSD-licensed driver. See LICENSE.
import Foundation

public enum AlphaWordCodec {
    public static func encode(_ text: String, limits: NeoFileLimits) throws -> Data {
        guard text.utf8.count <= 4 * 1024 * 1024 else {
            throw NeoError.tooLarge(required: text.utf8.count, maximum: limits.maximum)
        }
        let scalars = Array(text.unicodeScalars)
        var bytes: [UInt8] = []
        bytes.reserveCapacity(min(limits.maximum, max(limits.minimum, scalars.count)))
        var index = 0, softCount = 0, hardCount = 0
        var lastBreak: Int?
        while index < scalars.count {
            let scalar = scalars[index]; index += 1
            if scalar.value == 0xfeff { continue }
            if scalar.value == 13, index < scalars.count, scalars[index].value == 10 { index += 1 }
            let code: UInt8
            let escaped: Bool
            switch scalar.value {
            case 9: code = 9; escaped = false
            case 10, 13: code = 13; escaped = false
            default:
                let mapped = try NeoCharacters.encode(scalar)
                code = mapped == 0x81 ? 0xac : mapped
                // Phi and Pi also occupy AlphaWord line-control codes. Escape them to avoid data loss.
                escaped = (0xa1...0xbf).contains(code) || [9, 10, 13, 0x8d, 0x8f].contains(code)
            }
            softCount += 1; hardCount += 1
            if !escaped && code == 13 {
                lastBreak = nil; softCount = 0; hardCount = 0
            } else if !escaped && [0x2d, 0x20, 9].contains(code) {
                lastBreak = bytes.count; hardCount = 0
            } else if hardCount >= 24 {
                bytes.append(0x8f); hardCount = 0; softCount = 0; lastBreak = nil
            }
            if escaped { bytes.append(0xb0) }
            bytes.append(code)
            if escaped { bytes.append(0xb0) }
            if softCount >= 40, let last = lastBreak {
                switch bytes[last] {
                case 0x2d: bytes[last] = 0xad
                case 0x20: bytes[last] = 0x81
                default: bytes[last] = 0x8d
                }
                lastBreak = nil; softCount = 0; hardCount = 0
            }
            if bytes.count > limits.maximum {
                throw NeoError.tooLarge(required: bytes.count, maximum: limits.maximum)
            }
        }
        if bytes.count < limits.minimum { bytes += repeatElement(0xa7, count: limits.minimum - bytes.count) }
        return Data(bytes)
    }

    public static func decode(_ data: Data) throws -> String {
        guard data.count <= 0xffffff else { throw NeoError.invalidData("The text allocation is too large.") }
        let bytes = Array(data)
        var result = String.UnicodeScalarView()
        var index = 0
        while index < bytes.count {
            let code = bytes[index]; index += 1
            if code == 0xb0 {
                guard index + 1 < bytes.count else { throw NeoError.invalidData("An AlphaWord escape is truncated.") }
                result.append(NeoCharacters.decode(bytes[index])); index += 1
                if bytes[index] == 0xb0 { index += 1 }
                continue
            }
            switch code {
            case 0xa4, 0xa7, 0x8f: continue
            case 9, 0x8d, 0xa3: result.append("\t")
            case 10: result.append("\n")
            case 13: result.append("\r")
            case 0x81, 0xa1: result.append(" ")
            case 0xad: result.append("-")
            case 0xa1...0xbf: continue // Formatting controls are not text.
            default: result.append(NeoCharacters.decode(code))
            }
        }
        return String(result)
    }
}
