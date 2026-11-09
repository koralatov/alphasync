import CoreTransferable
import UniformTypeIdentifiers
import AlphaSyncCore
import AlphaSyncHardware

struct FileDrag: Transferable, Sendable {
    let file: NeoFileID
    let service: DeviceService
    let staging: TemporaryExports
    var contentType: UTType { FileCodec.fileExtension(applet: file.applet) == "txt" ? .plainText : .xml }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .plainText) { item in try await item.exportFile() }
            .exportingCondition { $0.contentType == .plainText }
        FileRepresentation(exportedContentType: .xml) { item in try await item.exportFile() }
            .exportingCondition { $0.contentType == .xml }
    }

    func exportFile() async throws -> SentTransferredFile {
        let temporary = try await staging.createFolder()
        do {
            let urls = try await service.export([file], to: temporary)
            guard let url = urls.first else { throw NeoError.device("The file could not be exported.") }
            await staging.retain(temporary)
            return SentTransferredFile(url, allowAccessingOriginalFile: false)
        } catch {
            await staging.discard(temporary)
            throw error
        }
    }
}
