// swift-tools-version: 6.1
import CompilerPluginSupport
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
        ),
        .library(
            name: "ProtoLawMacro",
            targets: ["ProtoLawMacro"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/x-sheep/swift-property-based.git", from: "1.0.0"),
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "600.0.0")
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
        ),

        // User-facing macro target — declarations only. Re-exports
        // ProtocolLawKit so users importing ProtoLawMacro can call the
        // generated `checkXxxProtocolLaws` functions without a second import.
        .target(
            name: "ProtoLawMacro",
            dependencies: [
                "ProtocolLawKit",
                "ProtoLawMacroImpl"
            ]
        ),
        // Compiler-plugin target hosting the macro implementation. Plugin
        // targets compile against swift-syntax and run during macro expansion.
        .macro(
            name: "ProtoLawMacroImpl",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
                .product(name: "SwiftDiagnostics", package: "swift-syntax")
            ]
        ),
        .testTarget(
            name: "ProtoLawMacroTests",
            dependencies: [
                "ProtoLawMacro",
                "ProtoLawMacroImpl",
                "ProtocolLawKit",
                .product(name: "PropertyBased", package: "swift-property-based"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax")
            ]
        ),

        // Whole-module discovery (PRD §5.3) — the cross-file form M1's
        // peer macro can't implement, delivered as a CommandPlugin that
        // walks all `.swift` files in a target and emits a generated test
        // file. The plugin is intentionally thin; the executable tool
        // does the actual SwiftSyntax work.
        .executableTarget(
            name: "ProtoLawDiscoveryTool",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax")
            ]
        ),
        .plugin(
            name: "ProtoLawDiscoveryPlugin",
            capability: .command(
                intent: .custom(
                    verb: "protolawcheck",
                    description: """
                        Generate ProtocolLawKit test files by walking a target's source files \
                        and detecting stdlib protocol conformances.
                        """
                ),
                permissions: [
                    .writeToPackageDirectory(reason:
                        "ProtoLawDiscoveryPlugin writes a generated test file (default: " +
                        "Tests/<Target>Tests/ProtocolLawTests.generated.swift) listing the " +
                        "checkXxxProtocolLaws calls for each detected conformance."
                    )
                ]
            ),
            dependencies: [
                "ProtoLawDiscoveryTool"
            ]
        ),
        .testTarget(
            name: "ProtoLawDiscoveryToolTests",
            dependencies: [
                "ProtoLawDiscoveryTool",
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax")
            ]
        )
    ]
)
