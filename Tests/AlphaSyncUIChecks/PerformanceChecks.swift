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
        let report: [String: Any] = ["kind": "AlphaSyncFileListComparison",
            "configuration": "SwiftPM debug checker; same host and fixture; warm cache",
            "fileCount": 64, "iterations": iterations,
            "repeatedSortSeconds": baseline.seconds, "cachedAccessSeconds": cached.seconds,
            "resultsMatched": true, "timingThreshold": "none; diagnostic only"]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("performance-checks.json"), options: .atomic)
        InterfaceChecks.checkpoint("File-list performance comparison saved")
        try checkSizeFormatting(to: output)
    }

    private static func checkSizeFormatting(to output: URL) throws {
        let sizes = [0, 1, 2, 999, 1_000, 1_024, 12_000, 51_200, 65_536, 378_880, 16_777_215]
        let previous: @MainActor @Sendable (Int) -> String = { value in
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file; formatter.allowedUnits = [.useBytes, .useKB]
            formatter.allowsNonnumericFormatting = false
            return formatter.string(fromByteCount: Int64(value))
        }
        let expected = sizes.map { previous($0) }
        let actual = sizes.map { FileSize.compact($0) }
        try InterfaceChecks.require(actual == expected, "File-size formatting changed: previous \(expected), current \(actual)")
        NotificationCenter.default.post(name: NSLocale.currentLocaleDidChangeNotification, object: nil)
        try InterfaceChecks.require(sizes.map { FileSize.compact($0) } == expected, "Locale invalidation changed file-size labels")
        let iterations = 100
        func measure(_ format: @MainActor (Int) -> String) -> (seconds: Double, characters: Int) {
            var characters = 0
            let duration = ContinuousClock().measure {
                for _ in 0..<iterations { for size in sizes { characters += format(size).count } }
            }
            let parts = duration.components
            return (Double(parts.seconds) + Double(parts.attoseconds) / 1e18, characters)
        }
        let baseline = measure(previous), reusable = measure(FileSize.compact)
        try InterfaceChecks.require(baseline.characters == reusable.characters, "The formatter comparison lost results")
        let report: [String: Any] = ["kind": "AlphaSyncFileSizeFormattingComparison", "locale": Locale.current.identifier,
            "configuration": "SwiftPM debug checker; same host, values, and locale; warm reused formatter",
            "sizes": sizes, "formatted": actual, "iterations": iterations,
            "freshFormatterSeconds": baseline.seconds, "reusedFormatterSeconds": reusable.seconds,
            "resultsMatched": true, "timingThreshold": "none; diagnostic only"]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("formatting-performance.json"), options: .atomic)
        InterfaceChecks.checkpoint("File-size formatting and diagnostic comparison saved")
    }
}
