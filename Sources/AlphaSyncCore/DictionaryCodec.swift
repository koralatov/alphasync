// Dictionary layout derived from tSoniq’s BSD-licensed ASUserDictionaryFile. See LICENSE.
import Foundation

public enum DictionaryCodec {
    public static let maximum = 65536
    public static func encode(_ text: String) throws -> Data {
        guard text.utf8.count <= 4 * 1024 * 1024 else { throw NeoError.tooLarge(required: text.utf8.count, maximum: maximum) }
        var words = Set<[UInt8]>(), current: [UInt8] = []
        func isSeparator(_ byte: UInt8) -> Bool {
            byte == 32 || (9...13).contains(byte) || (33...47).contains(byte) ||
            (58...64).contains(byte) || (91...96).contains(byte) || (123...126).contains(byte)
        }
        func finish() {
            if (2...20).contains(current.count) { words.insert(current) }
            current.removeAll(keepingCapacity: true)
        }
        for scalar in text.unicodeScalars {
            if scalar.value == 0xfeff { continue }
            let byte: UInt8 = [9, 10, 13].contains(scalar.value) ? 32 : try NeoCharacters.encode(scalar)
            if isSeparator(byte) { finish() } else { current.append(byte) }
        }
        finish()
        var header = Data(), body = Data()
        for length in 2...20 {
            let offset = 38 + body.count
            guard offset <= 65535 else { throw NeoError.tooLarge(required: offset, maximum: maximum) }
            header.appendBigEndian(UInt32(offset), width: 2)
            for word in words.filter({ $0.count == length }).sorted(by: { $0.lexicographicallyPrecedes($1) }) {
                guard body.count <= maximum - 38 - word.count else {
                    throw NeoError.tooLarge(required: 38 + body.count + word.count, maximum: maximum)
                }
                body.append(contentsOf: word)
            }
        }
        return header + body
    }

    public static func decode(_ data: Data) throws -> String {
        guard (38...maximum).contains(data.count) else { throw NeoError.invalidData("The dictionary has an invalid size.") }
        let r = BinaryReader(data)
        var offsets: [Int] = []
        for index in 0..<19 { offsets.append(Int(try r.integer(at: index * 2, width: 2))) }
        offsets.append(data.count)
        var words: [String] = []
        for index in 0..<19 {
            let start = offsets[index], end = offsets[index + 1], length = index + 2
            guard start >= 38, end >= start, end <= data.count, (end - start) % length == 0 else {
                throw NeoError.invalidData("Dictionary word offsets are invalid.")
            }
            for offset in stride(from: start, to: end, by: length) {
                let bytes = try r.data(at: offset, count: length)
                guard !bytes.contains(0) else { throw NeoError.invalidData("A dictionary word contains an invalid zero byte.") }
                words.append(String(String.UnicodeScalarView(bytes.map(NeoCharacters.decode))))
            }
        }
        return words.joined(separator: " ")
    }
}
