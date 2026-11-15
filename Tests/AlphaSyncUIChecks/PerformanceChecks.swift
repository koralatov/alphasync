import Foundation
import AlphaSyncCore
@testable import AlphaSyncUI

/// A diagnostic comparison with build 159’s repeated sort, not a device throughput benchmark.
@MainActor
enum PerformanceChecks {
    static func run(to output: URL) throws {
        let domain = "AlphaSync-PerformanceChecks-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let preferences = Preferences(defaults: defaults, loginItem: InterfaceLoginItem())
        let store = AppStore(preferences: preferences, monitoringEnabled: false)
        let snapshot = try InterfaceChecks.sample(fileCount: 64)
        store.devices = [snapshot]
        store.sidebar = .device(snapshot.connection)
        func uncached() -> [NeoFile] {
            let applets = snapshot.applets.filter { preferences.filter.appletIDs?.contains($0.id) ?? true }
            return applets.flatMap(\.files).sorted {
                $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
            }
        }
        let expected = uncached()
        try InterfaceChecks.require(store.files == expected, "Caching changed the file list or its sort order")
        let iterations = 500
        func measure(_ read: () -> [NeoFile]) -> (seconds: Double, count: Int) {
            var count = 0
            let duration = ContinuousClock().measure {
                for _ in 0..<iterations { count += read().count }
            }
            let parts = duration.components
            return (Double(parts.seconds) + Double(parts.attoseconds) / 1e18, count)
        }
        let baseline = measure(uncached)
        let cached = measure { store.files }
        try InterfaceChecks.require(baseline.count == 64 * iterations && cached.count == baseline.count,
                                    "The file-list comparison lost results")
        let report: [String: Any] = ["kind": "AlphaSyncFileListComparison", "build": "160",
            "configuration": "SwiftPM debug checker; same host and fixture; warm cache",
            "fileCount": 64, "iterations": iterations,
            "repeatedSortSeconds": baseline.seconds, "cachedAccessSeconds": cached.seconds,
            "resultsMatched": true, "timingThreshold": "none; diagnostic only"]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("performance-checks.json"), options: .atomic)
        InterfaceChecks.checkpoint("File-list performance comparison saved")
    }
}
