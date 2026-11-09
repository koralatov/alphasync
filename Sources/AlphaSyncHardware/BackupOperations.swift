import Foundation
import AlphaSyncCore

public struct BackupProgress: Sendable {
    public let saved: Int
    public let expected: Int
    public let fileName: String
}

extension DeviceService {
    public func backup(connections: [UUID], includedApplets: Set<UInt16>?, destination: URL,
                       saveLog: Bool, stop: StopRequest,
                       progress: @escaping @Sendable (BackupProgress) -> Void) async throws -> BackupResult {
        try await perform { access in
            // Validate all included lists before creating folders or treating a prefix as a complete backup.
            let snapshots = try connections.map { try access.update($0) }
            let expected = snapshots.reduce(0) { total, snapshot in
                total + snapshot.applets.filter { includedApplets?.contains($0.id) ?? true }.reduce(0) { $0 + $1.files.count }
            }
            var saved = 0, folders: [URL] = [], failures: [String] = []
            for snapshot in snapshots {
                if stop.isRequested { break }
                let applets = snapshot.applets.filter { includedApplets?.contains($0.id) ?? true }
                let files = applets.flatMap { applet in applet.files.map { (applet, $0) } }
                if files.isEmpty { continue }
                let root = destination.appendingPathComponent(snapshot.name, isDirectory: true)
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.calendar = Calendar(identifier: .gregorian)
                formatter.dateFormat = "yyyy-MM-dd"
                let pending: URL
                do { pending = try AtomicFileStore.createFolder(in: root, name: formatter.string(from: Date()), incomplete: true) }
                catch { failures.append("A backup folder could not be created: \(error.localizedDescription)"); break }
                folders.append(pending)
                var entries: [[String: Any]] = files.map { ["applet": $0.0.name, "file": $0.1.displayName, "status": "pending"] }
                var failed = false, logFailed = false
                func writeLog(_ status: String) throws {
                    guard saveLog else { return }
                    let report: [String: Any] = ["formatVersion": 3, "status": status, "files": entries]
                    let data = try PropertyListSerialization.data(fromPropertyList: report, format: .xml, options: 0)
                    try AtomicFileStore.updateBackupLog(data, in: pending)
                }
                do { try writeLog("running") }
                catch { failures.append("The backup log could not be created: \(error.localizedDescription)"); failed = true; logFailed = true }
                var appletFolders: [UInt16: URL] = [:]
                if !logFailed {
                    for (index, entry) in files.enumerated() {
                        if stop.isRequested { break }
                        let (applet, file) = entry
                        progress(BackupProgress(saved: saved, expected: expected, fileName: file.displayName))
                        do {
                            let engine = try access.engine(for: snapshot.connection)
                            let raw = try engine.readFile(applet: applet.id, index: file.id.index)
                            let text = try FileCodec.text(raw, applet: applet)
                            let folder: URL
                            if let existing = appletFolders[applet.id] { folder = existing }
                            else {
                                folder = try AtomicFileStore.createFolder(in: pending, name: applet.name)
                                appletFolders[applet.id] = folder
                            }
                            let output = try AtomicFileStore.write(TextFiles.utf8(text), name: file.displayName,
                                                                    extension: FileCodec.fileExtension(applet: applet.id), to: folder)
                            entries[index]["status"] = "saved"
                            entries[index]["path"] = folder.lastPathComponent + "/" + output.lastPathComponent
                            saved += 1
                        } catch {
                            failed = true
                            let message = "\(file.displayName): \(error.localizedDescription)"
                            failures.append(message); entries[index]["status"] = "failed"; entries[index]["error"] = message
                        }
                        do { try writeLog("running") }
                        catch {
                            failed = true; logFailed = true
                            failures.append("The backup log could not be updated: \(error.localizedDescription)")
                            break
                        }
                    }
                }
                if !logFailed {
                    do { try writeLog(stop.isRequested ? "cancelled" : (failed ? "incomplete" : "complete")) }
                    catch { failed = true; failures.append("The final backup log could not be saved: \(error.localizedDescription)") }
                }
                if !failed && !stop.isRequested {
                    do {
                        let final = try AtomicFileStore.completeFolder(pending)
                        folders[folders.count - 1] = final
                    } catch {
                        failures.append("The files were copied, but their folder could not be marked complete: \(error.localizedDescription)")
                        try? writeLog("incomplete")
                    }
                }
            }
            progress(BackupProgress(saved: saved, expected: expected, fileName: ""))
            return BackupResult(saved: saved, expected: expected, folders: folders, stopped: stop.isRequested, failures: failures)
        }
    }
}
