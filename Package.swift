// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AlphaSync",
    platforms: [.macOS(.v13)],
    products: [.library(name: "AlphaSyncCore", targets: ["AlphaSyncCore"]), .library(name: "AlphaSyncHardware", targets: ["AlphaSyncHardware"])],
    targets: [
        .target(name: "AlphaSyncCore"),
        .target(name: "AlphaSyncHardware", dependencies: ["AlphaSyncCore"], linkerSettings: [.linkedFramework("IOUSBHost"), .linkedFramework("IOKit")]),
        .testTarget(name: "AlphaSyncCoreTests", dependencies: ["AlphaSyncCore"])
    ]
)
