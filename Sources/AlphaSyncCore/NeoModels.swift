// Protocol layouts derived from tSoniq’s BSD-licensed AlphaSync driver. See LICENSE.
import Foundation

public struct NeoFileID: Hashable, Codable, Sendable {
    public let connection: UUID
    public let applet: UInt16
    public let index: UInt8

    public init(connection: UUID, applet: UInt16, index: UInt8) {
        self.connection = connection; self.applet = applet; self.index = index
    }
}

public struct NeoFileAttributes: Equatable, Sendable {
    public static let size = 40
    public private(set) var raw: Data
    public var name: String { (try? BinaryReader(raw).string(at: 0, count: 16)) ?? "" }
    public var password: String { (try? BinaryReader(raw).string(at: 16, count: 8)) ?? "" }
    public var minimum: Int { Int((try? BinaryReader(raw).integer(at: 24, width: 4)) ?? 0) }
    public var allocation: Int { Int((try? BinaryReader(raw).integer(at: 28, width: 4)) ?? 0) }
    public var flags: UInt32 { (try? BinaryReader(raw).integer(at: 32, width: 4)) ?? 0 }
    private static let spaces: [UInt8] = [0xff, 0x2d, 0x2c, 0x04, 0x0f, 0x0e, 0x0a, 0x01, 0x27]
    public var fileSpace: Int { Self.spaces.firstIndex(of: raw[raw.startIndex + 37]) ?? 0 }

    public init(raw: Data) throws {
        guard raw.count == Self.size else { throw NeoError.invalidData("File attributes have the wrong length.") }
        let reader = BinaryReader(raw)
        _ = try reader.string(at: 0, count: 16)
        _ = try reader.string(at: 16, count: 8)
        self.raw = Data(Array(raw))
    }

    public init(name: String, minimum: Int = 512, allocation: Int = 512, fileSpace: Int = 0) throws {
        guard minimum >= 0, minimum <= Int(UInt32.max), allocation >= 0, allocation <= Int(UInt32.max),
              (0...8).contains(fileSpace) else { throw NeoError.invalidData("Invalid file attributes.") }
        raw = Data(repeating: 0, count: Self.size)
        try rename(name)
        raw.replaceSubrange(16..<22, with: Data("write".utf8) + Data([0]))
        var sizes = Data(); sizes.appendBigEndian(UInt32(minimum), width: 4)
        sizes.appendBigEndian(UInt32(allocation), width: 4)
        raw.replaceSubrange(24..<32, with: sizes)
        raw[37] = Self.spaces[fileSpace]
    }

    public mutating func rename(_ name: String) throws {
        guard !name.isEmpty, !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              let encoded = name.data(using: .windowsCP1252, allowLossyConversion: false), encoded.count <= 15 else {
            throw NeoError.device("Use a name of 1 to 15 supported characters, without line breaks.")
        }
        raw.replaceSubrange(0..<16, with: encoded + Data(repeating: 0, count: 16 - encoded.count))
    }
}

public struct NeoApplet: Identifiable, Hashable, Sendable {
    public static let alphaWord: UInt16 = 0xa000
    public static let dictionary: UInt16 = 0xa005
    public static let headerSize = 132
    public let id: UInt16
    public let name: String
    public let information: String
    public let major: UInt8
    public let minor: UInt8
    public let revision: UInt8
    public let flags: UInt32
    public let romSize: Int
    public let workspace: Int
    public var files: [NeoFile] = []
    public var ramUsed: Int = 0
    public var limits: NeoFileLimits?
    public var version: String { "\(major).\(minor)" + (revision > 32 ? String(UnicodeScalar(revision)) : "") }
    public var canWrite: Bool { id == Self.alphaWord || id == Self.dictionary }

    public init(header: Data) throws {
        guard header.count == Self.headerSize else { throw NeoError.invalidData("An applet header is truncated.") }
        let r = BinaryReader(header)
        guard try r.integer(at: 0, width: 4) == 0xc0ffeead else { throw NeoError.invalidData("An applet signature is invalid.") }
        id = UInt16(try r.integer(at: 20, width: 2))
        name = try r.string(at: 24, count: 36)
        information = try r.string(at: 64, count: 60)
        major = UInt8(try r.integer(at: 60, width: 1)); minor = UInt8(try r.integer(at: 61, width: 1))
        revision = UInt8(try r.integer(at: 62, width: 1)); flags = try r.integer(at: 16, width: 4)
        romSize = Int(try r.integer(at: 4, width: 4)); workspace = Int(try r.integer(at: 8, width: 4))
    }
}

public struct NeoFile: Identifiable, Hashable, Sendable {
    public let id: NeoFileID
    public let name: String
    public let size: Int
    public let fileSpace: Int
    public let password: String
    public let allocation: Int
    public init(id: NeoFileID, attributes: NeoFileAttributes, size: Int) {
        self.id = id; name = attributes.name; self.size = size
        fileSpace = attributes.fileSpace; password = attributes.password; allocation = attributes.allocation
    }
    public var displayName: String { name.isEmpty ? (fileSpace > 0 ? "File \(fileSpace)" : "Untitled") : name }
}

public struct NeoSnapshot: Sendable {
    public let connection: UUID
    public let registryID: UInt64
    public let name: String
    public let systemVersion: String
    public let availableRAM: Int
    public let availableROM: Int
    public let applets: [NeoApplet]

    public init(connection: UUID, registryID: UInt64, name: String = "Neo", systemVersion: String,
                availableRAM: Int, availableROM: Int, applets: [NeoApplet]) {
        self.connection = connection; self.registryID = registryID; self.name = name
        self.systemVersion = systemVersion; self.availableRAM = availableRAM
        self.availableROM = availableROM; self.applets = applets
    }
}

public struct NeoFileLimits: Hashable, Sendable {
    public let minimum: Int
    public let maximum: Int
    public init(minimum: Int, maximum: Int) throws {
        guard minimum >= 0, maximum > 0, minimum <= maximum, maximum <= 0xffffff else {
            throw NeoError.limitsUnavailable
        }
        self.minimum = minimum; self.maximum = maximum
    }
    public func validate(_ size: Int, allocation: Int, available: Int) throws {
        guard size <= maximum else { throw NeoError.tooLarge(required: size, maximum: maximum) }
        let growth = max(0, size - allocation)
        let usable = max(0, available - 1024)
        if growth > usable { throw NeoError.insufficientMemory(required: growth, available: usable) }
    }
}
