import Foundation
#if os(macOS)
import Darwin
#endif

public enum TextFiles {
    public static let maximumImportBytes = 4 * 1024 * 1024

    public static func read(_ url: URL) throws -> String {
        #if os(macOS)
        // Non-blocking open avoids waiting on a named pipe before the regular-file check.
        let descriptor = open(url.path, O_RDONLY | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        #else
        let handle = try FileHandle(forReadingFrom: url)
        #endif
        defer { try? handle.close() }
        #if os(macOS)
        var attributes = stat()
        guard fstat(handle.fileDescriptor, &attributes) == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        guard attributes.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else {
            throw NeoError.device("Choose a regular text file.  Folders, devices, and named pipes cannot be imported.")
        }
        #endif
        let data = try handle.read(upToCount: maximumImportBytes + 1) ?? Data()
        guard data.count <= maximumImportBytes else {
            throw NeoError.device("This text file is larger than AlphaSync’s \(maximumImportBytes.formatted())-byte import limit.  Shorten it or split it into smaller files.")
        }
        return try decode(data)
    }

    public static func decode(_ data: Data) throws -> String {
        guard data.count <= maximumImportBytes else { throw NeoError.invalidData("The import is too large.") }
        if data.starts(with: [0xff, 0xfe]) || data.starts(with: [0xfe, 0xff]) {
            guard data.count % 2 == 0, let text = String(data: data, encoding: .utf16) else {
                throw NeoError.device("The UTF-16 text file is damaged or incomplete.")
            }
            return text
        }
        if data.starts(with: [0xef, 0xbb, 0xbf]) {
            guard let text = String(data: data.dropFirst(3), encoding: .utf8) else {
                throw NeoError.device("The UTF-8 text file is damaged or incomplete.")
            }
            return text
        }
        if let text = String(data: data, encoding: .utf8) { return text }
        guard let text = String(data: data, encoding: .macOSRoman) else {
            throw NeoError.device("This file is not supported text. Use MacASCII, UTF-8, or UTF-16.")
        }
        return text
    }

    public static func utf8(_ text: String) -> Data {
        Data(text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").utf8)
    }
}
