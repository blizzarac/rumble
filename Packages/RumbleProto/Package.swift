// swift-tools-version: 6.0
import PackageDescription

// Generated gRPC/protobuf code lives only in this package so it compiles once
// and stays out of the UI. The .proto files in Sources/RumbleProto are the
// starting point for the interface alignment, not the final contract.
//
// Requires `protoc` on the build machine (brew install protobuf).
let package = Package(
    name: "RumbleProto",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "RumbleProto", targets: ["RumbleProto"]),
    ],
    dependencies: [
        .package(path: "../RumbleServices"),
        .package(url: "https://github.com/grpc/grpc-swift.git", from: "2.0.0"),
        .package(url: "https://github.com/grpc/grpc-swift-protobuf.git", from: "1.0.0"),
        .package(url: "https://github.com/grpc/grpc-swift-nio-transport.git", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.28.0"),
    ],
    targets: [
        .target(
            name: "RumbleProto",
            dependencies: [
                "RumbleServices",
                .product(name: "GRPCCore", package: "grpc-swift"),
                .product(name: "GRPCProtobuf", package: "grpc-swift-protobuf"),
                .product(name: "GRPCNIOTransportHTTP2", package: "grpc-swift-nio-transport"),
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
            ],
            plugins: [
                .plugin(name: "GRPCProtobufGenerator", package: "grpc-swift-protobuf"),
            ]
        ),
        .testTarget(name: "RumbleProtoTests", dependencies: ["RumbleProto", "RumbleServices"]),
    ]
)
