// swift-tools-version: 6.1
import PackageDescription

/// Validation pass 2 (PRD §8): wires `ProtocolLawKit` against an
/// external Swift package and runs actual law checks. Lives in its own
/// SwiftPM package so the external dep doesn't leak into the kit's main
/// manifest — consumers of SwiftProtocolLaws never see swift-argument-parser.
///
/// Run with:
///   cd Validation && swift test
let package = Package(
    name: "ValidationPass2",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(name: "SwiftProtocolLaws", path: ".."),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.6.0")
    ],
    targets: [
        .testTarget(
            name: "ValidationPass2Tests",
            dependencies: [
                // ProtocolLawKit re-exports PropertyBased (`@_exported import`),
                // so a direct dep on it isn't needed here.
                .product(name: "ProtocolLawKit", package: "SwiftProtocolLaws"),
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        )
    ]
)
