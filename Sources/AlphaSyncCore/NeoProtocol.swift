// Wire protocol derived from tSoniq’s BSD-licensed ASDevice.cc. See LICENSE.
import Foundation

/// The owner confines this transport and its engine to one serial I/O executor.
public protocol NeoTransport: AnyObject {
    func read(maximum: Int, timeout: TimeInterval) throws -> Data
    func write(_ data: Data, timeout: TimeInterval) throws
    func close()
}

public final class NeoProtocol {
    private let transport: any NeoTransport
    private static let reset = Data([0x3f, 0xff, 0, 0x72, 0x65, 0x73, 0x65, 0x74])
    private let timeout: TimeInterval

    public init(transport: any NeoTransport, timeout: TimeInterval = 20) {
        self.transport = transport; self.timeout = timeout
    }
    public func close() { transport.close() }

    private func transaction<T>(_ operation: () throws -> T) throws -> T {
        try transport.write(Data([1]), timeout: 0.5)
        let version = try transport.read(maximum: 8, timeout: 0.5)
        guard version.count == 2, try BinaryReader(version).integer(at: 0, width: 2) >= 0x0230 else {
            throw NeoError.device("The Neo did not enter file-transfer mode. Reconnect it and try again.")
        }
        try transport.write(Self.reset, timeout: timeout)
        defer { try? transport.write(Self.reset, timeout: timeout) }
        try transport.write(Data([0x3f, 0x53, 0x77, 0x74, 0x63, 0x68, 0, 0]), timeout: timeout)
        guard try readExactly(8) == Data("Switched".utf8) else { throw NeoError.invalidData("The system applet did not acknowledge selection.") }
        return try operation()
    }

    private func readExactly(_ count: Int) throws -> Data {
        guard (0...0xffffff).contains(count) else { throw NeoError.invalidData("A transfer length is invalid.") }
        var result = Data()
        result.reserveCapacity(count)
        let deadline = Date().addingTimeInterval(timeout)
        while result.count < count {
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { throw NeoError.device("The Neo did not finish its reply in time. Reconnect it and try again.") }
            let block = try transport.read(maximum: min(8, count - result.count), timeout: remaining)
            guard !block.isEmpty, block.count <= count - result.count else { throw NeoError.invalidData("A reply is incomplete.") }
            result.append(block)
        }
        return result
    }

    private func receive() throws -> NeoMessage { try NeoMessage(data: readExactly(8)) }
    private func send(_ message: NeoMessage, expecting code: UInt8) throws -> NeoMessage {
        try transport.write(message.data, timeout: timeout)
        let reply = try receive()
        guard reply.command == code else {
            throw NeoError.device("The Neo could not complete the request (reply \(String(format: "0x%02X", reply.command))). Reconnect it and try again.")
        }
        return reply
    }
    private func command(_ code: UInt8, value: UInt32 = 0, applet: UInt16 = 0) throws -> NeoMessage {
        var result = NeoMessage(command: code)
        try result.set(value, at: 1, width: 4)
        try result.set(UInt32(applet), at: 5, width: 2)
        return result
    }
    private func checkedPayload(_ reply: NeoMessage, maximum: Int, versionQuirk: Bool = false) throws -> Data {
        let size = Int(try reply.argument(at: 1, width: 4))
        guard size <= maximum else { throw NeoError.invalidData("The advertised reply exceeds its allowed size.") }
        let data = try readExactly(size)
        let actual = data.reduce(UInt32(0)) { ($0 + UInt32($1)) & 0xffff }
        let expected = try reply.argument(at: 5, width: 2)
        if actual != expected {
            let b = Array(data)
            let difference = (actual &+ 65536 &- expected) & 0xffff
            let known = versionQuirk && b.count >= 8 && b[4] == 3 && [4, 6].contains(b[5]) && [1, 65535].contains(difference)
            guard known else { throw NeoError.invalidData("A data checksum is invalid.") }
        }
        return data
    }

    public func appletHeaders() throws -> [NeoApplet] {
        try transaction {
            var result: [NeoApplet] = [], seen = Set<UInt16>()
            while result.count < 256 {
                var request = NeoMessage(command: 4)
                try request.set(UInt32(result.count), at: 1, width: 4)
                try request.set(7, at: 5, width: 2)
                let reply = try send(request, expecting: 0x44)
                let data = try checkedPayload(reply, maximum: NeoApplet.headerSize * 7)
                guard data.count % NeoApplet.headerSize == 0 else { throw NeoError.invalidData("An applet header is incomplete.") }
                let count = data.count / NeoApplet.headerSize
                for index in 0..<count {
                    let applet = try NeoApplet(header: BinaryReader(data).data(at: index * NeoApplet.headerSize, count: NeoApplet.headerSize))
                    guard seen.insert(applet.id).inserted else { throw NeoError.invalidData("An applet identifier was repeated.") }
                    result.append(applet)
                }
                if count < 7 { return result }
            }
            throw NeoError.invalidData("The applet list did not terminate.")
        }
    }

    public func availableMemory() throws -> (ram: Int, rom: Int) {
        try transaction {
            let reply = try send(NeoMessage(command: 0x1a), expecting: 0x58)
            return (Int(try reply.argument(at: 5, width: 2)) * 256, Int(try reply.argument(at: 1, width: 4)))
        }
    }
    public func resourceUsage(applet: UInt16) throws -> (count: Int, ram: Int) {
        try transaction {
            let reply = try send(command(0x1b, value: 1, applet: applet), expecting: 0x59)
            let count = Int(try reply.argument(at: 5, width: 2))
            guard count <= 255 else { throw NeoError.invalidData("The file count exceeds the protocol’s index range.") }
            return (count, Int(try reply.argument(at: 1, width: 4)))
        }
    }
    public func attributes(applet: UInt16, index: UInt8) throws -> NeoFileAttributes {
        guard index > 0 else { throw NeoError.invalidData("A file index is invalid.") }
        return try transaction {
            let reply = try send(command(0x13, value: UInt32(index), applet: applet), expecting: 0x5a)
            return try NeoFileAttributes(raw: checkedPayload(reply, maximum: 40))
        }
    }
    public func fileLimits(applet: UInt16) throws -> NeoFileLimits {
        if applet == NeoApplet.dictionary { return try NeoFileLimits(minimum: 0, maximum: DictionaryCodec.maximum) }
        guard applet == NeoApplet.alphaWord else { throw NeoError.device("This applet’s file format is read-only.") }
        return try transaction {
            let reply = try send(command(0x0c, value: 0x0b, applet: applet), expecting: 0x4b)
            return try NeoSettings.alphaWordLimits(checkedPayload(reply, maximum: 8192))
        }
    }
    public func systemVersion() throws -> String {
        try transaction {
            let reply = try send(NeoMessage(command: 0), expecting: 0x40)
            let data = try checkedPayload(reply, maximum: 1024, versionQuirk: true)
            let r = BinaryReader(data)
            guard data.count >= 8, let nameEnd = r.bytes[6...].firstIndex(of: 0), nameEnd + 1 < data.count,
                  r.bytes[(nameEnd + 1)...].contains(0) else { throw NeoError.invalidData("The system version is incomplete.") }
            return "\(try r.integer(at: 4, width: 1)).\(try r.integer(at: 5, width: 1))"
        }
    }

    private func rawRead(applet: UInt16, index: UInt8, maximum: Int) throws -> Data {
        guard (0...0xffffff).contains(maximum) else { throw NeoError.invalidData("A file allocation is invalid.") }
        var request = NeoMessage(command: 0x1c)
        try request.set(UInt32(maximum), at: 1, width: 3)
        try request.set(UInt32(index), at: 4, width: 1)
        try request.set(UInt32(applet), at: 5, width: 2)
        _ = try send(request, expecting: 0x53)
        var result = Data()
        result.reserveCapacity(maximum)
        while result.count < maximum {
            try transport.write(NeoMessage(command: 0x10).data, timeout: timeout)
            let reply = try receive()
            if reply.command == 0x4e { break }
            guard reply.command == 0x4d else { throw NeoError.invalidData("A file block has an unexpected reply.") }
            let count = Int(try reply.argument(at: 1, width: 4))
            guard count > 0, count <= 1024, count <= maximum - result.count else {
                throw NeoError.invalidData("A file block exceeds the requested range.")
            }
            result.append(try checkedPayload(reply, maximum: min(1024, maximum - result.count)))
        }
        return result
    }
    public func readFile(applet: UInt16, index: UInt8) throws -> Data {
        let info = try attributes(applet: applet, index: index)
        guard info.allocation <= 0xffffff else { throw NeoError.invalidData("The file allocation is too large.") }
        return try transaction { try rawRead(applet: applet, index: index, maximum: max(1, info.allocation)) }
    }

    private func writeBlocks(_ data: Data) throws {
        let r = BinaryReader(data)
        var offset = 0
        while offset < data.count {
            let block = try r.data(at: offset, count: min(1024, data.count - offset))
            let checksum = block.reduce(UInt32(0)) { ($0 + UInt32($1)) & 0xffff }
            var request = NeoMessage(command: 2)
            try request.set(UInt32(block.count), at: 1, width: 4)
            try request.set(checksum, at: 5, width: 2)
            _ = try send(request, expecting: 0x42)
            try transport.write(block, timeout: timeout)
            guard try receive().command == 0x43 else { throw NeoError.invalidData("A data block was not acknowledged.") }
            offset += block.count
        }
    }
    private func rawWrite(_ data: Data, applet: UInt16, index: UInt8) throws {
        var request = NeoMessage(command: 0x1f)
        try request.set(UInt32(index), at: 1, width: 1)
        try request.set(UInt32(data.count), at: 2, width: 3)
        try request.set(UInt32(applet), at: 5, width: 2)
        _ = try send(request, expecting: 0x50)
        try writeBlocks(data)
        _ = try send(NeoMessage(command: 0x15), expecting: 0x51)
        let readback = try rawRead(applet: applet, index: index, maximum: max(1, data.count))
        guard readback == data else { throw NeoError.verificationFailed }
    }
    private func rawAttributes(_ attributes: NeoFileAttributes, applet: UInt16, index: UInt8) throws {
        try attributes.validateForWriting()
        _ = try send(command(0x1d, value: UInt32(index), applet: applet), expecting: 0x5b)
        try writeBlocks(attributes.raw)
        var commit = NeoMessage(command: 0x1e)
        try commit.set(UInt32(index), at: 4, width: 1)
        try commit.set(UInt32(applet), at: 5, width: 2)
        _ = try send(commit, expecting: 0x5c)
    }

    /// Validation happens again immediately before the transaction that can change device contents.
    private func changing<T>(_ operation: () throws -> T) throws -> T {
        do { return try operation() }
        catch { throw NeoWriteError(reason: error.localizedDescription) }
    }

    public func writeFile(_ data: Data, applet: UInt16, index: UInt8, expectedOriginal: Data) throws {
        let limits = try fileLimits(applet: applet)
        let info = try attributes(applet: applet, index: index)
        let memory = try availableMemory()
        try limits.validate(data.count, allocation: info.allocation, available: memory.ram)
        guard try readFile(applet: applet, index: index) == expectedOriginal else {
            throw NeoError.device("The file changed after the warning opened. Review the current file and try again. No device files were changed.")
        }
        try transaction { try changing { try rawWrite(data, applet: applet, index: index) } }
    }
    public func createFile(_ data: Data, name: String, applet: UInt16) throws -> UInt8 {
        let limits = try fileLimits(applet: applet)
        let memory = try availableMemory()
        try limits.validate(data.count, allocation: 0, available: memory.ram)
        let usage = try resourceUsage(applet: applet)
        guard usage.count < 255 else { throw NeoError.device("The applet cannot hold another file.") }
        let index = UInt8(usage.count + 1)
        let attributes = try NeoFileAttributes(name: name, minimum: data.count, allocation: data.count)
        try transaction {
            try changing {
                try rawAttributes(attributes, applet: applet, index: index)
                try rawWrite(data, applet: applet, index: index)
            }
        }
        return index
    }
    public func rename(applet: UInt16, index: UInt8, to name: String) throws {
        var info = try attributes(applet: applet, index: index)
        try info.rename(name)
        try info.validateForWriting()
        try changing {
            try transaction { try rawAttributes(info, applet: applet, index: index) }
            guard try attributes(applet: applet, index: index).name == name else { throw NeoError.verificationFailed }
        }
    }

    public func snapshot(connection: UUID, registryID: UInt64) throws -> NeoSnapshot {
        var applets = try appletHeaders()
        guard applets.contains(where: { $0.id == 0 }) else { throw NeoError.invalidData("The system applet is missing.") }
        let version = try systemVersion(), memory = try availableMemory()
        for position in applets.indices {
            let id = applets[position].id
            let before = try resourceUsage(applet: id)
            var files: [NeoFile] = []
            if before.count > 0 {
                for index in 1...before.count {
                    let info = try attributes(applet: id, index: UInt8(index))
                    files.append(NeoFile(id: NeoFileID(connection: connection, applet: id, index: UInt8(index)), attributes: info, size: info.allocation))
                }
            }
            let after = try resourceUsage(applet: id)
            guard after.count == before.count else { throw NeoError.invalidData("The file list changed while it was being read. Reconnect and try again.") }
            applets[position].files = files; applets[position].ramUsed = after.ram
            if applets[position].canWrite { applets[position].limits = try? fileLimits(applet: id) }
        }
        return NeoSnapshot(connection: connection, registryID: registryID, systemVersion: version,
                           availableRAM: memory.ram, availableROM: memory.rom, applets: applets)
    }
}
