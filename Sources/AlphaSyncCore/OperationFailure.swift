import Foundation

public enum FileChangeAction: Sendable {
    case add, change, rename

    var pastTense: String {
        switch self {
        case .add: return "added"
        case .change: return "changed"
        case .rename: return "renamed"
        }
    }
}

/// Facts about a failed operation are kept independently of its displayed wording.
public struct OperationFailure: Error, LocalizedError, Sendable {
    public let underlying: any Error
    public let action: FileChangeAction
    public let completedFiles: Int
    public let currentFileMayHaveChanged: Bool
    public let recoveryFolder: URL?

    public init(_ error: any Error, action: FileChangeAction, completedFiles: Int = 0, recoveryFolder: URL? = nil) {
        self.action = action
        if let previous = error as? OperationFailure {
            underlying = previous.underlying
            self.completedFiles = completedFiles + previous.completedFiles
            currentFileMayHaveChanged = previous.currentFileMayHaveChanged
            self.recoveryFolder = recoveryFolder ?? previous.recoveryFolder
        } else if let write = error as? NeoWriteError {
            underlying = write.underlying
            self.completedFiles = completedFiles
            currentFileMayHaveChanged = true
            self.recoveryFolder = recoveryFolder
        } else {
            underlying = error
            self.completedFiles = completedFiles
            currentFileMayHaveChanged = false
            self.recoveryFolder = recoveryFolder
        }
    }

    public var errorDescription: String? {
        var parts = [underlying.localizedDescription]
        if completedFiles > 0 {
            let files = completedFiles == 1 ? "file was" : "files were"
            parts.append("\(completedFiles.formatted()) \(files) \(action.pastTense) and verified before the operation stopped.")
        }
        if currentFileMayHaveChanged {
            parts.append("The current file may already have changed.  Check the Neo and your recovery copy before trying again.")
        } else if completedFiles == 0 {
            parts.append("No device files were changed.")
        }
        if let recoveryFolder {
            parts.append("\n\nRecovery copy: \(recoveryFolder.path)")
        }
        return parts.joined(separator: "  ")
    }
}
