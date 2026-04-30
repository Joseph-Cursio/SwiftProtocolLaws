// swift-tools-version: 6.1
import CompilerPluginSupport
import PackageDescription

let package = Package(
    name: "SwiftProtocolLaws",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
        .tvOS(.v17),
        .watchOS(.v10),
        .visionOS(.v1)
    ],
    products: [
        .library(
            name: "ProtocolLawKit",
            targets: ["ProtocolLawKit"]
        ),
        .library(
            name: "ProtoLawMacro",
            targets: ["ProtoLawMacro"]
        ),
        // PRD §5.7 generator-derivation strategist exposed as its own
        // shipped library so downstream tools (SwiftInferProperties M3+,
        // per its PRD §11) call into the shared priority order rather than
        // reimplementing it. The module's public surface is just the
        // strategist + its input/output value types — `KnownProtocol` and
        // `MemberwiseEmitter` stay `package`-scoped for now (M1 of the
        // SwiftInferProperties cross-validation work doesn't need either).
        .library(
            name: "ProtoLawCore",
            targets: ["ProtoLawCore"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/x-sheep/swift-property-based.git", from: "1.0.0"),
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "600.0.0")
        // `swift-property-based` is the single property-based backend.
        // The PRD §4.5 `PropertyBackend` abstraction stays public — its
        // closure-level seam is non-leaky, and a future second backend can
        // drop in without protocol changes — but v1 deliberately ships a
        // single best-of-breed implementation rather than chasing parity
        // for its own sake.
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

        // Shared core target. The §5.7 generator-derivation strategist is
        // exposed publicly via the `ProtoLawCore` product (added v1.6.0)
        // for downstream consumption by SwiftInferProperties M3+. The
        // PRD §4.3 `KnownProtocol` enum and the `MemberwiseEmitter`
        // text-renderer stay `package`-scoped — they're consumed only by
        // `ProtoLawMacroImpl` and `ProtoLawDiscoveryTool` inside this
        // package and aren't part of the shipped API contract.
        .target(
            name: "ProtoLawCore",
            dependencies: []
        ),
        .testTarget(
            name: "ProtoLawCoreTests",
            dependencies: ["ProtoLawCore"]
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
                "ProtoLawCore",
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
                "ProtoLawCore",
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
