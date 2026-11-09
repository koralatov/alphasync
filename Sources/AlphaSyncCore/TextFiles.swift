import Foundation

public enum TextFiles {
    public static let maximumImportBytes = 4 * 1024 * 1024

    public static func read(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: maximumImportBytes + 1) ?? Data()
        guard data.count <= maximumImportBytes else {
            throw NeoError.device("This text file is larger than AlphaSync’s \(maximumImportBytes.formatted())-byte import limit. Shorten it or split it into smaller files. No device files were changed.")
        }
        return try decode(data)
    }

    public static func decode(_ data: Data) throws -> String {
        guard data.count <= maximumImportBytes else { throw NeoError.invalidData("The import is too large.") }
        if data.starts(with: [0xff, 0xfe]) || data.starts(with: [0xfe, 0xff]) {
            guard data.count % 2 == 0, let text = String(data: data, encoding: .utf16) else {
                throw NeoError.device("The UTF-16 text file is damaged or incomplete. No device files were changed.")
            }
            return text
        }
        if let text = String(data: data, encoding: .utf8) {
            return text.hasPrefix("\u{feff}") ? String(text.dropFirst()) : text
        }
        guard let text = String(data: data, encoding: .macOSRoman) else {
            throw NeoError.device("This file is not supported text. Use MacASCII, UTF-8, or UTF-16.")
        }
        return text
    }

    public static func utf8(_ text: String) -> Data {
        Data(text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").utf8)
    }
}
