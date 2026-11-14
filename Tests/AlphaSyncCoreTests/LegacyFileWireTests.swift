import Foundation
import XCTest
@testable import AlphaSyncCore

/// Independent v1.5.1 byte layouts, including write acknowledgements and checksums.
private final class LegacyFileWire: NeoTransport {
    var file = Data(repeating: 0xa7, count: 512)
    var requests: [[UInt8]] = []
    var uploads: [Data] = []
    var corruptReadback = false
    private var incoming = Data(), staged = Data(), reading = Data()
    private var metadata: [UInt32: Data] = [:]
    private var attributeTarget: UInt32?, fileTarget: UInt32?
    private var fileLength = 0, commits = 0, alphaWordCount: UInt16 = 8
    private var block: (size: Int, checksum: UInt16)?

    private func packet(_ fields: [UInt8]) -> Data {
        precondition(fields.count == 7)
        return Data(fields + [fields.reduce(UInt8(0), &+)])
    }
    private func integer(_ bytes: [UInt8], _ range: Range<Int>) -> UInt32 {
        range.reduce(UInt32(0)) { ($0 << 8) | UInt32(bytes[$1]) }
    }
    private func reply(_ code: UInt8, value: UInt32 = 0, tail: UInt16 = 0) {
        incoming.append(packet([code, UInt8(truncatingIfNeeded: value >> 24),
            UInt8(truncatingIfNeeded: value >> 16), UInt8(truncatingIfNeeded: value >> 8),
            UInt8(truncatingIfNeeded: value), UInt8(tail >> 8), UInt8(truncatingIfNeeded: tail)]))
    }
    private func payload(_ code: UInt8, _ data: Data) {
        reply(code, value: UInt32(data.count), tail: data.reduce(UInt16(0)) { $0 &+ UInt16($1) })
        incoming.append(data)
    }
    private func attributes() -> Data {
        var bytes = [UInt8](repeating: 0, count: 40)
        bytes.replaceSubrange(0..<8, with: Array("Existing".utf8))
        bytes.replaceSubrange(16..<21, with: Array("write".utf8))
        bytes[26] = 2; bytes[30] = 2; bytes[37] = 0xff
        return Data(bytes)
    }

    func read(maximum: Int, timeout: TimeInterval) throws -> Data {
        guard !incoming.isEmpty else { throw NeoError.device("No pending legacy-wire reply.") }
        let data = Data(incoming.prefix(maximum))
        incoming.removeFirst(data.count)
        return data
    }

    func write(_ data: Data, timeout: TimeInterval) throws {
        if let block {
            guard data.count == block.size, data.reduce(UInt16(0), { $0 &+ UInt16($1) }) == block.checksum else {
                throw NeoError.invalidData("Wrong legacy block length or checksum.")
            }
            staged.append(data); uploads.append(data); self.block = nil
            reply(0x43)
            return
        }
        if data == Data([1]) { incoming.append(contentsOf: [2, 0x30]); return }
        if data == Data([0x3f, 0xff, 0, 0x72, 0x65, 0x73, 0x65, 0x74]) {
            incoming.removeAll(); staged.removeAll(); reading.removeAll()
            attributeTarget = nil; fileTarget = nil
            return
        }
        if data == Data([0x3f, 0x53, 0x77, 0x74, 0x63, 0x68, 0, 0]) {
            incoming.append(Data("Switched".utf8)); return
        }
        let bytes = Array(data)
        guard bytes.count == 8, bytes.prefix(7).reduce(UInt8(0), &+) == bytes[7] else {
            throw NeoError.invalidData("Invalid legacy command checksum.")
        }
        requests.append(bytes)
        let applet = integer(bytes, 5..<7)
        if [0x13, 0x1b, 0x1c, 0x1d, 0x1e, 0x1f].contains(bytes[0]), applet != 0xa000 && applet != 0xa005 {
            throw NeoError.invalidData("Unexpected legacy applet.")
        }
        switch bytes[0] {
        case 0x0c:
            guard data == packet([0x0c, 0, 0, 0, 0x0b, 0xa0, 0]) else { break }
            payload(0x4b, Data([1, 2, 0x10, 0x10, 0, 4, 0, 0, 0xc8, 0,
                1, 2, 0x10, 0x11, 0, 4, 0, 0, 2, 0])); return
        case 0x1a:
            guard data == packet([0x1a, 0, 0, 0, 0, 0, 0]) else { break }
            reply(0x58, tail: 256); return
        case 0x1b:
            guard Array(bytes[1...4]) == [0, 0, 0, 1] else { break }
            reply(0x59, tail: applet == 0xa000 ? alphaWordCount : 1); return
        case 0x13:
            guard Array(bytes[1...3]) == [0, 0, 0], bytes[4] > 0 else { break }
            payload(0x5a, metadata[applet << 8 | UInt32(bytes[4])] ?? attributes()); return
        case 0x1c:
            guard bytes[4] > 0 else { break }
            reading = Data(file.prefix(Int(integer(bytes, 1..<4))))
            if corruptReadback && commits > 0 && !reading.isEmpty { reading[0] ^= 1 }
            reply(0x53); return
        case 0x10:
            guard data == packet([0x10, 0, 0, 0, 0, 0, 0]) else { break }
            if reading.isEmpty { reply(0x4e) }
            else {
                let chunk = Data(reading.prefix(1024)); reading.removeFirst(chunk.count)
                payload(0x4d, chunk)
            }
            return
        case 0x1d:
            guard Array(bytes[1...3]) == [0, 0, 0], bytes[4] > 0 else { break }
            attributeTarget = applet << 8 | UInt32(bytes[4]); staged.removeAll()
            reply(0x5b); return
        case 0x02:
            let size = Int(integer(bytes, 1..<5))
            guard attributeTarget != nil || fileTarget != nil, (1...1024).contains(size) else { break }
            block = (size, UInt16(integer(bytes, 5..<7)))
            reply(0x42); return
        case 0x1e:
            guard Array(bytes[1...3]) == [0, 0, 0], staged.count == 40,
                  attributeTarget == applet << 8 | UInt32(bytes[4]) else { break }
            metadata[applet << 8 | UInt32(bytes[4])] = staged
            if applet == 0xa000 { alphaWordCount = max(alphaWordCount, UInt16(bytes[4])) }
            attributeTarget = nil; staged.removeAll()
            reply(0x5c); return
        case 0x1f:
            guard bytes[1] > 0 else { break }
            fileTarget = applet << 8 | UInt32(bytes[1])
            fileLength = Int(integer(bytes, 2..<5)); staged.removeAll()
            reply(0x50); return
        case 0x15:
            guard data == packet([0x15, 0, 0, 0, 0, 0, 0]), fileTarget != nil,
                  staged.count == fileLength else { break }
            file = staged; fileTarget = nil; commits += 1
            reply(0x51); return
        default: break
        }
        throw NeoError.invalidData("Unexpected legacy file request: \(bytes).")
    }
    func close() {}
    func requests(_ command: UInt8) -> [[UInt8]] { requests.filter { $0[0] == command } }
}

final class LegacyFileWireTests: XCTestCase {
    func testReplacementUsesLegacyOffsetsBlocksChecksumsAndReadback() throws {
        let wire = LegacyFileWire(), data = Data((0..<2304).map { UInt8(truncatingIfNeeded: $0) })
        try NeoProtocol(transport: wire).writeFile(data, applet: 0xa000, index: 1, expectedOriginal: wire.file)
        XCTAssertEqual(wire.requests(0x1f).map { Array($0.prefix(7)) }, [[0x1f, 1, 0, 9, 0, 0xa0, 0]])
        XCTAssertEqual(wire.uploads.map(\.count), [1024, 1024, 256])
        XCTAssertEqual(wire.uploads.reduce(Data(), +), data)
        XCTAssertEqual(wire.requests(0x15).count, 1)
        XCTAssertEqual(wire.requests(0x1c).map { Array($0.prefix(7)) },
            [[0x1c, 0, 2, 0, 1, 0xa0, 0], [0x1c, 0, 9, 0, 1, 0xa0, 0]])
        XCTAssertEqual(wire.file, data)
    }

    func testCreationCommitsFortyByteAttributesBeforeWritingNewIndex() throws {
        let wire = LegacyFileWire(), data = Data(repeating: 65, count: 512)
        let index = try NeoProtocol(transport: wire).createFile(data, name: "New File", applet: 0xa000)
        XCTAssertEqual(index, 9)
        XCTAssertEqual(wire.requests.suffix(8).map { $0[0] }, [0x1d, 2, 0x1e, 0x1f, 2, 0x15, 0x1c, 0x10])
        XCTAssertEqual(wire.requests(0x1d).map { Array($0.prefix(7)) }, [[0x1d, 0, 0, 0, 9, 0xa0, 0]])
        XCTAssertEqual(wire.requests(0x1e).map { Array($0.prefix(7)) }, [[0x1e, 0, 0, 0, 9, 0xa0, 0]])
        XCTAssertEqual(wire.requests(0x1f).map { Array($0.prefix(7)) }, [[0x1f, 9, 0, 2, 0, 0xa0, 0]])
        var attributes = Data("New File".utf8) + Data(repeating: 0, count: 8)
        attributes.append(Data("write".utf8) + Data(repeating: 0, count: 3))
        attributes.append(contentsOf: [0, 0, 2, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0xff, 0, 0])
        XCTAssertEqual(wire.uploads, [attributes, data])
        XCTAssertEqual(wire.file, data)
    }

    func testRenamePreservesOtherAttributesAndNeverWritesFileContents() throws {
        let wire = LegacyFileWire(), original = wire.file
        try NeoProtocol(transport: wire).rename(applet: 0xa000, index: 1, to: "Renamed")
        XCTAssertEqual(wire.requests.map { $0[0] }, [0x13, 0x1d, 2, 0x1e, 0x13])
        XCTAssertEqual(wire.uploads.first?.count, 40)
        XCTAssertEqual(wire.uploads.first?.prefix(16), Data("Renamed".utf8) + Data(repeating: 0, count: 9))
        XCTAssertEqual(wire.uploads.first?.subdata(in: 16..<24), Data("write".utf8) + Data(repeating: 0, count: 3))
        XCTAssertEqual(wire.file, original)
    }

    func testEmptyDictionaryUsesZeroLengthFileAndEOFWithoutADataBlock() throws {
        let wire = LegacyFileWire()
        try NeoProtocol(transport: wire).writeFile(Data(), applet: 0xa005, index: 1, expectedOriginal: wire.file)
        XCTAssertEqual(wire.requests(0x1f).map { Array($0.prefix(7)) }, [[0x1f, 1, 0, 0, 0, 0xa0, 5]])
        XCTAssertTrue(wire.requests(2).isEmpty)
        XCTAssertTrue(wire.uploads.isEmpty)
        XCTAssertEqual(wire.requests(0x15).count, 1)
        XCTAssertTrue(wire.file.isEmpty)
    }

    func testCorruptReadbackIsAWriteFailureWithoutReplayOrFalsePreservationClaim() {
        let wire = LegacyFileWire(); wire.corruptReadback = true
        XCTAssertThrowsError(try NeoProtocol(transport: wire).writeFile(Data(repeating: 66, count: 512),
            applet: 0xa000, index: 1, expectedOriginal: wire.file)) {
            XCTAssertNotNil($0 as? NeoWriteError)
            XCTAssertTrue($0.localizedDescription.contains("may already have changed"))
        }
        XCTAssertEqual(wire.requests(0x1f).count, 1)
        XCTAssertEqual(wire.requests(0x15).count, 1)
        XCTAssertEqual(wire.file, Data(repeating: 66, count: 512))
    }
}
