// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RumbleServices",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "RumbleServices", targets: ["RumbleServices"]),
    ],
    targets: [
        .target(name: "RumbleServices"),
        .testTarget(name: "RumbleServicesTests", dependencies: ["RumbleServices"]),
    ]
)
