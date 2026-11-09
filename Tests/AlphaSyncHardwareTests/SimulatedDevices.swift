import Foundation
import AlphaSyncCore
@testable import AlphaSyncHardware

struct SimulatedConfiguration: Sendable {
    var fileCount = 2
    var failingRead: UInt8?
    var failingWriteNumber: Int?
    var failRefreshAfterWriting = false
    var beforeRead: (@Sendable (UInt8) -> Void)?
    var failOpen = false
    var appletID = NeoApplet.alphaWord
}

/// Only observations cross executors.  Device data remains inside the simulated connection.
final class SimulatedObservations: @unchecked Sendable {
    private let lock = NSLock()
    private var attached: [UInt64] = [1]
    private var writes = 0
    private var closes = 0
    private var opens = 0
    private var retries: [Bool] = []
    private var scans = 0

    func didScan() {
        lock.lock()
        defer { lock.unlock() }
        scans += 1
    }
    var scanCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return scans
    }

    func didOpen() {
        lock.lock()
        defer { lock.unlock() }
        opens += 1
    }

    func didCheckModeSwitch(retryFailures: Bool) {
        lock.lock()
        defer { lock.unlock() }
        retries.append(retryFailures)
    }

    var openCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return opens
    }

    var modeSwitchRetries: [Bool] {
        lock.lock()
        defer { lock.unlock() }
        return retries
    }

    func setAttached(_ ids: [UInt64]) {
        lock.lock()
        defer { lock.unlock() }
        attached = ids
    }

    func attachedIDs() -> [UInt64] {
        lock.lock()
        defer { lock.unlock() }
        return attached
    }

    func didWrite() {
        lock.lock()
        defer { lock.unlock() }
        writes += 1
    }

    func didClose() {
        lock.lock()
        defer { lock.unlock() }
        closes += 1
    }

    var writeCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return writes
    }

    var closeCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return closes
    }
}

final class SimulatedDiscovery: DeviceDiscovery {
    private let configuration: SimulatedConfiguration
    private let observations: SimulatedObservations

    init(_ configuration: SimulatedConfiguration, _ observations: SimulatedObservations) {
        self.configuration = configuration
        self.observations = observations
    }

    func devices() throws -> [any DeviceAttachment] {
        observations.didScan()
        return observations.attachedIDs().map {
            SimulatedAttachment(registryID: $0, configuration: configuration, observations: observations)
        }
    }

    func modeSwitchIssue(retryFailures: Bool) -> String? {
        observations.didCheckModeSwitch(retryFailures: retryFailures)
        return nil
    }
}

private final class SimulatedAttachment: DeviceAttachment {
    let registryID: UInt64
    private let configuration: SimulatedConfiguration
    private let observations: SimulatedObservations

    init(registryID: UInt64, configuration: SimulatedConfiguration, observations: SimulatedObservations) {
        self.registryID = registryID
        self.configuration = configuration
        self.observations = observations
    }

    func open() throws -> any DeviceConnection {
        observations.didOpen()
        if configuration.failOpen { throw NeoError.device("Simulated open failure") }
        return try SimulatedConnection(configuration, observations)
    }
}

private final class SimulatedConnection: DeviceConnection {
    private let configuration: SimulatedConfiguration
    private let observations: SimulatedObservations
    private let limits: NeoFileLimits
    private var contents: [UInt8: Data] = [:]
    private var names: [UInt8: String] = [:]
    private var writes = 0

    init(_ configuration: SimulatedConfiguration, _ observations: SimulatedObservations) throws {
        self.configuration = configuration
        self.observations = observations
        limits = try NeoFileLimits(minimum: configuration.appletID == NeoApplet.dictionary ? 0 : 512,
                                   maximum: configuration.appletID == NeoApplet.dictionary ? DictionaryCodec.maximum : 51_200)
        guard (0...255).contains(configuration.fileCount) else { throw NeoError.invalidData("Invalid simulated file count") }
        for number in 0..<configuration.fileCount {
            let index = UInt8(number + 1)
            switch configuration.appletID {
            case NeoApplet.alphaWord: contents[index] = try AlphaWordCodec.encode("Original \(number + 1)", limits: limits)
            case NeoApplet.dictionary: contents[index] = try DictionaryCodec.encode("Original")
            default: contents[index] = Data([index, 0, 1, 2])
            }
            names[index] = "File \(number + 1)"
        }
    }

    func close() { observations.didClose() }

    func snapshot(connection: UUID, registryID: UInt64) throws -> NeoSnapshot {
        if configuration.failRefreshAfterWriting && writes > 0 { throw NeoError.disconnected }
        var header = Data(repeating: 0, count: NeoApplet.headerSize)
        header.replaceSubrange(0..<4, with: [0xc0, 0xff, 0xee, 0xad])
        header[20] = UInt8(configuration.appletID >> 8)
        header[21] = UInt8(configuration.appletID & 0xff)
        let name = configuration.appletID == NeoApplet.alphaWord ? "AlphaWord" : "Test Applet"
        header.replaceSubrange(24..<(24 + name.utf8.count), with: Data(name.utf8))
        var applet = try NeoApplet(header: header)
        applet.limits = limits
        applet.files = try contents.keys.sorted().map { index in
            let info = try attributes(applet: applet.id, index: index)
            return NeoFile(id: NeoFileID(connection: connection, applet: applet.id, index: index),
                           attributes: info, size: info.allocation)
        }
        return NeoSnapshot(connection: connection, registryID: registryID, systemVersion: "3.6",
                           availableRAM: 300_000, availableROM: 1_000_000, applets: [applet])
    }

    func fileLimits(applet: UInt16) throws -> NeoFileLimits { limits }
    func availableMemory() throws -> (ram: Int, rom: Int) { (300_000, 1_000_000) }

    func attributes(applet: UInt16, index: UInt8) throws -> NeoFileAttributes {
        guard let bytes = contents[index], let name = names[index] else { throw NeoError.disconnected }
        return try NeoFileAttributes(name: name, allocation: bytes.count, fileSpace: Int(index) <= 8 ? Int(index) : 0)
    }

    func readFile(applet: UInt16, index: UInt8, checkingCancellation: () throws -> Void) throws -> Data {
        try checkingCancellation()
        configuration.beforeRead?(index)
        try checkingCancellation()
        if configuration.failingRead == index { throw NeoError.device("Simulated read failure") }
        guard let bytes = contents[index] else { throw NeoError.disconnected }
        return bytes
    }

    func writeFile(_ data: Data, applet: UInt16, index: UInt8, expectedOriginal: Data) throws {
        guard contents[index] == expectedOriginal else { throw NeoError.device("The original changed") }
        writes += 1
        observations.didWrite()
        contents[index] = data
        if configuration.failingWriteNumber == writes { throw NeoWriteError(underlying: NeoError.verificationFailed) }
    }

    func createFile(_ data: Data, name: String, applet: UInt16) throws -> UInt8 {
        let index = UInt8(contents.count + 1)
        writes += 1
        observations.didWrite()
        contents[index] = data
        names[index] = name
        return index
    }

    func rename(applet: UInt16, index: UInt8, to name: String) throws {
        guard contents[index] != nil else { throw NeoError.disconnected }
        writes += 1
        observations.didWrite()
        names[index] = name
    }
}
