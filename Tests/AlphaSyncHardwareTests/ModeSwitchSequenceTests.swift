import Foundation
import XCTest
@testable import AlphaSyncHardware

private enum ModeSwitchFixtureError: Error { case descriptor, configuration, report }

private final class RecordedModeSwitch: ModeSwitchConnection {
    var configuration: UInt8 = 3
    var failDescriptor = false
    var failConfiguration = false
    var failReport: Int?
    var reportCount: Int?
    var events: [String] = []
    var requests: [ModeSwitchRequest] = []
    var timeouts: [TimeInterval] = []
    var closes = 0

    func firstConfiguration() throws -> UInt8 {
        events.append("read configuration")
        if failDescriptor { throw ModeSwitchFixtureError.descriptor }
        return configuration
    }

    func configure(_ value: UInt8) throws {
        events.append("configure \(value)")
        if failConfiguration { throw ModeSwitchFixtureError.configuration }
    }

    func send(_ request: ModeSwitchRequest, timeout: TimeInterval) throws -> Int {
        events.append(String(format: "report %02x", request.data.first ?? 0))
        requests.append(request)
        timeouts.append(timeout)
        if requests.count == failReport { throw ModeSwitchFixtureError.report }
        return reportCount ?? 1
    }

    func close() { events.append("close"); closes += 1 }
}

final class ModeSwitchSequenceTests: XCTestCase {
    func testConfigurationAndReportsMatchTheWorkingLegacyUSBSequence() throws {
        let connection = RecordedModeSwitch()
        try NeoModeSwitch.perform(connection)
        XCTAssertEqual(connection.events, ["read configuration", "configure 3", "report e0", "report e1",
                                            "report e2", "report e3", "report e4", "close"])
        XCTAssertEqual(connection.requests.map(\.data), [Data([0xe0]), Data([0xe1]), Data([0xe2]), Data([0xe3]), Data([0xe4])])
        for request in connection.requests {
            XCTAssertEqual(request.requestType, 0x21) // Host-to-device, class, interface.
            XCTAssertEqual(request.request, 9)       // HID SET_REPORT.
            XCTAssertEqual(request.value, 0x0200)    // Output report, ID 0.
            XCTAssertEqual(request.index, 1)
        }
        XCTAssertEqual(connection.timeouts, [5, 5, 5, 5, 5])
        XCTAssertEqual(connection.closes, 1)
    }

    func testAnInvalidConfigurationSendsNoCommandsAndClosesTheDevice() {
        let connection = RecordedModeSwitch()
        connection.configuration = 0
        XCTAssertThrowsError(try NeoModeSwitch.perform(connection))
        XCTAssertEqual(connection.events, ["read configuration", "close"])
        XCTAssertTrue(connection.requests.isEmpty)
        XCTAssertEqual(connection.closes, 1)
    }

    func testDescriptorFailureSendsNoCommandsAndClosesTheDevice() {
        let connection = RecordedModeSwitch()
        connection.failDescriptor = true
        XCTAssertThrowsError(try NeoModeSwitch.perform(connection))
        XCTAssertEqual(connection.events, ["read configuration", "close"])
        XCTAssertTrue(connection.requests.isEmpty)
        XCTAssertEqual(connection.closes, 1)
    }

    func testConfigurationFailureSendsNoReportsAndClosesTheDevice() {
        let connection = RecordedModeSwitch()
        connection.failConfiguration = true
        XCTAssertThrowsError(try NeoModeSwitch.perform(connection))
        XCTAssertEqual(connection.events, ["read configuration", "configure 3", "close"])
        XCTAssertTrue(connection.requests.isEmpty)
        XCTAssertEqual(connection.closes, 1)
    }

    func testEveryReportFailureStopsTheSequenceWithoutRetryingAndClosesTheDevice() {
        let legacyReports = [Data([0xe0]), Data([0xe1]), Data([0xe2]), Data([0xe3]), Data([0xe4])]
        for failedReport in 1...5 {
            let connection = RecordedModeSwitch()
            connection.failReport = failedReport
            XCTAssertThrowsError(try NeoModeSwitch.perform(connection))
            XCTAssertEqual(connection.requests.map(\.data), Array(legacyReports.prefix(failedReport)))
            XCTAssertEqual(connection.events.last, "close")
            XCTAssertEqual(connection.closes, 1)
        }
    }

    func testShortAndInvalidTransferCountsStopBeforeTheNextReport() {
        for count in [-1, 0, 2] {
            let connection = RecordedModeSwitch()
            connection.reportCount = count
            XCTAssertThrowsError(try NeoModeSwitch.perform(connection))
            XCTAssertEqual(connection.requests.map(\.data), [Data([0xe0])])
            XCTAssertEqual(connection.events.last, "close")
            XCTAssertEqual(connection.closes, 1)
        }
    }
}
