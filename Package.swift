// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AlphaSync",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "AlphaSyncCore", targets: ["AlphaSyncCore"]),
        .library(name: "AlphaSyncHardware", targets: ["AlphaSyncHardware"]),
        .library(name: "AlphaSyncUI", targets: ["AlphaSyncUI"]),
        .executable(name: "AlphaSyncUIChecks", targets: ["AlphaSyncUIChecks"])
    ],
    targets: [
        .target(name: "AlphaSyncCore"),
        .target(name: "AlphaSyncHardware", dependencies: ["AlphaSyncCore"],
                linkerSettings: [.linkedFramework("IOUSBHost"), .linkedFramework("IOKit")]),
        .target(name: "AlphaSyncUI", dependencies: ["AlphaSyncCore", "AlphaSyncHardware"],
                linkerSettings: [.linkedFramework("ServiceManagement")]),
        .executableTarget(name: "AlphaSyncUIChecks", dependencies: ["AlphaSyncUI"], path: "Tests/AlphaSyncUIChecks"),
        .testTarget(name: "AlphaSyncCoreTests", dependencies: ["AlphaSyncCore"]),
        .testTarget(name: "AlphaSyncHardwareTests", dependencies: ["AlphaSyncHardware", "AlphaSyncUI"])
    ]
)
