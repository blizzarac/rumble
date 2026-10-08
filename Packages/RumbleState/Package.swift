// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RumbleState",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "RumbleState", targets: ["RumbleState"]),
    ],
    dependencies: [
        .package(path: "../RumbleServices"),
    ],
    targets: [
        .target(name: "RumbleState", dependencies: ["RumbleServices"]),
        .testTarget(name: "RumbleStateTests", dependencies: ["RumbleState"]),
    ]
)
