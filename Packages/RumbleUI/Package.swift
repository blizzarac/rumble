// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RumbleUI",
    platforms: [.iOS(.v18)],
    products: [
        .library(name: "RumbleUI", targets: ["RumbleUI"]),
    ],
    dependencies: [
        .package(path: "../RumbleState"),
        .package(path: "../RumbleServices"),
    ],
    targets: [
        .target(
            name: "RumbleUI",
            dependencies: ["RumbleState", "RumbleServices"]
        ),
    ]
)
