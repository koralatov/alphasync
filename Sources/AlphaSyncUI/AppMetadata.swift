import Foundation

public enum AppMetadata {
    public static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "2.0.2" }
    public static var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Development" }
    public static var compatibility: String { Bundle.main.object(forInfoDictionaryKey: "ASCompatibilityDescription") as? String ?? "For macOS 13 and later" }
    public static let project = URL(string: "https://github.com/koralatov/alphasync")!
    public static var development: Bool { Bundle.main.object(forInfoDictionaryKey: "ASReleaseChannel") as? String != "stable" }
    public static var releaseNotes: URL {
        development ? project.appendingPathComponent("blob/master/releases/" + version + ".md") : project.appendingPathComponent("releases/tag/v" + version)
    }
    public static var licence: URL { project.appendingPathComponent(development ? "blob/master/LICENSE" : "blob/v" + version + "/LICENSE") }
    public static var issues: URL {
        var components = URLComponents(url: project.appendingPathComponent("issues/new"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "title", value: "AlphaSync \(version): "), URLQueryItem(name: "body", value: diagnostics + "\n\nWhat happened?\n\nWhat did you expect?\n")]
        return components.url ?? project.appendingPathComponent("issues")
    }
    public static var contact: URL {
        var components = URLComponents()
        components.scheme = "mailto"; components.path = "mike@koralatov.com"
        components.queryItems = [URLQueryItem(name: "subject", value: "AlphaSync \(version)"), URLQueryItem(name: "body", value: "\n\n" + diagnostics)]
        return components.url ?? URL(string: "mailto:mike@koralatov.com")!
    }
    public static var edition: String {
        Bundle.main.object(forInfoDictionaryKey: "ASBuildProfile") as? String ?? "Development"
    }
    public static var diagnostics: String {
        "AlphaSync \(version) (\(build))\nEdition: \(edition)\n\(compatibility)\n\(ProcessInfo.processInfo.operatingSystemVersionString)\n" + architecture
    }
    public static var architecture: String {
        #if arch(arm64)
        return "Apple Silicon (arm64)"
        #else
        return "Intel (x86_64)"
        #endif
    }
}
