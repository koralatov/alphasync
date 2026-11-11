import Foundation
import AlphaSyncCore

struct ModeSwitchRequest {
    let requestType: UInt8
    let request: UInt8
    let value: UInt16
    let index: UInt16
    let data: Data
}

protocol ModeSwitchConnection: AnyObject {
    func firstConfiguration() throws -> UInt8
    func configure(_ value: UInt8) throws
    func send(_ request: ModeSwitchRequest, timeout: TimeInterval) throws -> Int
    func close()
}

enum NeoModeSwitch {
    /// Match the USB configuration and control requests used by the working 1.5.1 driver.
    static func perform(_ connection: any ModeSwitchConnection) throws {
        defer { connection.close() }
        let configuration = try connection.firstConfiguration()
        guard configuration != 0 else { throw NeoError.invalidData("The Neo has no usable USB configuration.") }
        try connection.configure(configuration)
        for code: UInt8 in 0xe0...0xe4 {
            let request = ModeSwitchRequest(requestType: 0x21, request: 9, value: 0x0200,
                                            index: 1, data: Data([code]))
            guard try connection.send(request, timeout: 5) == 1 else {
                throw NeoError.device("The Neo accepted an incomplete mode-switch command.")
            }
        }
    }
}
