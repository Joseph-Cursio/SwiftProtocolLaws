// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "SwiftProtocolLaws",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "ProtocolLawKit",
            targets: ["ProtocolLawKit"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/x-sheep/swift-property-based.git", from: "1.0.0")
        // SwiftQC v1.0.0 (the only tagged release as of 2026-04-25) fails to
        // compile on Swift 6.3 — `Range+Arbitrary.swift:105` captures
        // `var val1`/`val2` in a `@Sendable` closure, which Swift 6.3 rejects
        // (#SendableClosureCaptures). Until SwiftQC publishes a fix the second
        // backend from PRD §4.8 stays deferred. The `PropertyBackend` protocol
        // (PRD §4.5) is shipped public and shaped at the closure-level seam
        // surfaced by the M4 dep survey, so when SwiftQC unblocks adding the
        // second backend is purely additive.
    ],
    targets: [
        .target(
            name: "ProtocolLawKit",
            dependencies: [
                .product(name: "PropertyBased", package: "swift-property-based")
            ]
        ),
        .testTarget(
            name: "ProtocolLawKitTests",
            dependencies: [
                "ProtocolLawKit",
                .product(name: "PropertyBased", package: "swift-property-based")
            ]
        )
    ]
)
