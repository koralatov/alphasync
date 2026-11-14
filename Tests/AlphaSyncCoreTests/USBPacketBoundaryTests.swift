import Foundation
import XCTest
@testable import AlphaSyncCore

/// Preserve USB packet boundaries rather than modelling the endpoint as a byte stream.
private final class PacketScript: NeoTransport {
    var packets: [Data]
    var reads: [(maximum: Int, timeout: TimeInterval)] = []
    var writes: [(data: Data, timeout: TimeInterval)] = []

    init(_ replies: [Data]) { packets = [Data([2, 0x30]), Data("Switched".utf8)] + replies }
    func read(maximum: Int, timeout: TimeInterval) throws -> Data {
        reads.append((maximum, timeout))
        guard !packets.isEmpty else { throw NeoError.device("Unexpected fixture read.") }
        return packets.removeFirst()
    }
    func write(_ data: Data, timeout: TimeInterval) throws { writes.append((data, timeout)) }
    func close() {}
}

final class USBPacketBoundaryTests: XCTestCase {
    private let version = Data([0, 0, 0, 0, 3, 6, 78, 101, 111, 0, 68, 97, 116, 101, 0])

    private func frame(_ code: UInt8, payload: Data) -> Data {
        let size = UInt32(payload.count)
        let sum = payload.reduce(UInt16(0)) { $0 &+ UInt16($1) }
        let fields: [UInt8] = [code, UInt8(truncatingIfNeeded: size >> 24),
            UInt8(truncatingIfNeeded: size >> 16), UInt8(truncatingIfNeeded: size >> 8),
            UInt8(truncatingIfNeeded: size), UInt8(sum >> 8), UInt8(truncatingIfNeeded: sum)]
        return Data(fields + [fields.reduce(UInt8(0), &+)])
    }

    func testShortCommandFrameIsNotJoinedToTheNextPacket() {
        let wire = PacketScript([Data([0x58, 0, 0, 0]), Data([0, 1, 0, 0x59])])
        XCTAssertThrowsError(try NeoProtocol(transport: wire).availableMemory())
        XCTAssertEqual(wire.reads.map(\.maximum), [8, 8, 8])
        XCTAssertEqual(wire.packets, [Data([0, 1, 0, 0x59])])
        XCTAssertEqual(wire.writes.filter { $0.data.first == 0x1a }.count, 1)
        XCTAssertEqual(wire.writes.last?.data, Data([0x3f, 0xff, 0, 0x72, 0x65, 0x73, 0x65, 0x74]))
    }

    func testShortPayloadStopsBeforeConsumingALaterPacket() {
        let wire = PacketScript([frame(0x40, payload: version), Data(version.prefix(8)),
            Data(version.dropFirst(8).prefix(3)), Data(version.suffix(4))])
        XCTAssertThrowsError(try NeoProtocol(transport: wire).systemVersion())
        XCTAssertEqual(wire.reads.map(\.maximum), [8, 8, 8, 8, 7])
        XCTAssertEqual(wire.packets, [Data(version.suffix(4))])
    }

    func testExactFinalTailAndTheIntentionallyShortHelloRemainValid() throws {
        let wire = PacketScript([frame(0x40, payload: version), Data(version.prefix(8)), Data(version.suffix(7))])
        XCTAssertEqual(try NeoProtocol(transport: wire).systemVersion(), "3.6")
        XCTAssertEqual(wire.reads.map(\.maximum), [8, 8, 8, 8, 7])
        XCTAssertEqual(wire.reads.first?.timeout, 0.1)
        XCTAssertEqual(wire.writes.first?.timeout, 0.1)
        XCTAssertTrue(wire.packets.isEmpty)
    }

    func testEmptyPacketEndsTheTransactionWithoutReplayingACommand() {
        let wire = PacketScript([Data(), Data([0x58, 0, 0, 0, 0, 1, 0, 0x59])])
        XCTAssertThrowsError(try NeoProtocol(transport: wire).availableMemory())
        XCTAssertEqual(wire.reads.count, 3)
        XCTAssertEqual(wire.packets.count, 1)
        XCTAssertEqual(wire.writes.filter { $0.data.first == 0x1a }.count, 1)
    }

    func testReplyLargerThanTheRequestedPacketIsRejected() {
        let wire = PacketScript([Data(repeating: 0, count: 9)])
        XCTAssertThrowsError(try NeoProtocol(transport: wire).availableMemory())
        XCTAssertEqual(wire.reads.map(\.maximum), [8, 8, 8])
    }
}
