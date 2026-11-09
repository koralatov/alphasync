import Foundation

/// A failed export retains the files already published on the Mac.
public struct ExportFailure: Error, LocalizedError, Sendable {
    public let underlying: any Error
    public let savedFiles: [URL]
    public let expectedFiles: Int
    public let destination: URL
    public var completedFiles: Int { savedFiles.count }

    public init(_ error: any Error, savedFiles: [URL], expectedFiles: Int, destination: URL) {
        underlying = error
        self.savedFiles = savedFiles
        self.expectedFiles = expectedFiles
        self.destination = destination
    }

    public var errorDescription: String? {
        let result: String
        if savedFiles.isEmpty {
            result = "No files were saved to:\n\(destination.path)"
        } else {
            let verb = savedFiles.count == 1 ? "was" : "were"
            result = "\(savedFiles.count.formatted()) of \(expectedFiles.formatted()) files \(verb) saved to:\n\(destination.path)\n\nThe saved files have been kept."
        }
        return underlying.localizedDescription + "\n\n" + result + "\n\nThe original files on your Neo have not been changed."
    }
}
