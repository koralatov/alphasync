// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AlphaSync",
    platforms: [.macOS(.v13)],
    products: [.library(name: "AlphaSyncCore", targets: ["AlphaSyncCore"])],
    targets: [
        .target(name: "AlphaSyncCore"),
        .testTarget(name: "AlphaSyncCoreTests", dependencies: ["AlphaSyncCore"])
    ]
)
