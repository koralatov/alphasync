import Foundation
import XCTest
import CoreTransferable
import UniformTypeIdentifiers
import AlphaSyncCore
@testable import AlphaSyncHardware
@testable import AlphaSyncUI

final class FileDragTests: XCTestCase {
    private func root() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        return folder
    }

    func testAdvertisedTypesMatchEachAppletFormat() throws {
        guard #available(macOS 15.2, *) else { throw XCTSkip("Inspecting Transferable content types requires macOS 15.2") }
        let service = DeviceService()
        let staging = TemporaryExports(root: try root())
        for (applet, expected) in [(NeoApplet.alphaWord, UTType.plainText), (NeoApplet.dictionary, .plainText), (UInt16(0xa002), .xml)] {
            let file = NeoFileID(connection: UUID(), applet: applet, index: 1)
            let drag = FileDrag(file: file, service: service, staging: staging)
            XCTAssertEqual(drag.exportedContentTypes(), [expected])
        }
    }

    func testDragPublishesTheMatchingTextOrXMLFile() async throws {
        for applet in [NeoApplet.alphaWord, UInt16(0xa002)] {
            let configuration = SimulatedConfiguration(appletID: applet)
            let observations = SimulatedObservations()
            let service = DeviceService(discoveryFactory: { SimulatedDiscovery(configuration, observations) })
            let result = try await service.scan()
            let file = try XCTUnwrap(result.devices.first?.applets.first?.files.first)
            let staging = TemporaryExports(root: try root())
            let drag = FileDrag(file: file.id, service: service, staging: staging)
            let sent = try await drag.exportFile()
            XCTAssertFalse(sent.allowAccessingOriginalFile)
            let text = try String(contentsOf: sent.file, encoding: .utf8)
            if applet == NeoApplet.alphaWord {
                XCTAssertEqual(sent.file.pathExtension, "txt")
                XCTAssertEqual(text, "Original 1")
            } else {
                XCTAssertEqual(sent.file.pathExtension, "xml")
                XCTAssertTrue(text.contains("<appletID>0xa002</appletID>"))
                XCTAssertTrue(text.contains("<data>01000102</data>"))
            }
            await staging.discard(sent.file.deletingLastPathComponent())
            XCTAssertTrue(FileManager.default.fileExists(atPath: sent.file.path))
            await service.shutdown()
        }
    }

    func testFailedDragRemovesItsUnpromisedTemporaryFolder() async throws {
        let configuration = SimulatedConfiguration(failingRead: 1)
        let observations = SimulatedObservations()
        let service = DeviceService(discoveryFactory: { SimulatedDiscovery(configuration, observations) })
        let result = try await service.scan()
        let file = try XCTUnwrap(result.devices.first?.applets.first?.files.first)
        let parent = try root()
        let staging = TemporaryExports(root: parent)
        let drag = FileDrag(file: file.id, service: service, staging: staging)
        do {
            _ = try await drag.exportFile()
            XCTFail("The simulated drag failure unexpectedly succeeded")
        } catch {
            let sessions = try FileManager.default.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil)
            let session = try XCTUnwrap(sessions.first)
            let contents = try FileManager.default.contentsOfDirectory(atPath: session.path)
            XCTAssertEqual(Set(contents), Set([".session-lock", ".session.plist"]))
        }
        await service.shutdown()
    }
}
