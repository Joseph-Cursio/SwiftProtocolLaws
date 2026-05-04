// swift-tools-version: 6.1
import CompilerPluginSupport
import PackageDescription

let package = Package(
    name: "SwiftPropertyLaws",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
        .tvOS(.v17),
        .watchOS(.v10),
        .visionOS(.v1)
    ],
    products: [
        .library(
            name: "PropertyLawKit",
            targets: ["PropertyLawKit"]
        ),
        .library(
            name: "PropertyLawMacro",
            targets: ["PropertyLawMacro"]
        ),
        // PRD §5.7 generator-derivation strategist exposed as its own
        // shipped library so downstream tools (SwiftInferProperties M3+,
        // per its PRD §11) call into the shared priority order rather than
        // reimplementing it. The module's public surface is just the
        // strategist + its input/output value types — `KnownProtocol` and
        // `MemberwiseEmitter` stay `package`-scoped for now (M1 of the
        // SwiftInferProperties cross-validation work doesn't need either).
        .library(
            name: "PropertyLawCore",
            targets: ["PropertyLawCore"]
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
            name: "PropertyLawKit",
            dependencies: [
                .product(name: "PropertyBased", package: "swift-property-based")
            ]
        ),
        .testTarget(
            name: "PropertyLawKitTests",
            dependencies: [
                "PropertyLawKit",
                .product(name: "PropertyBased", package: "swift-property-based")
            ]
        ),

        // Shared core target. The §5.7 generator-derivation strategist is
        // exposed publicly via the `PropertyLawCore` product (added v1.6.0)
        // for downstream consumption by SwiftInferProperties M3+. The
        // PRD §4.3 `KnownProtocol` enum and the `MemberwiseEmitter`
        // text-renderer stay `package`-scoped — they're consumed only by
        // `PropertyLawMacroImpl` and `PropertyLawDiscoveryTool` inside this
        // package and aren't part of the shipped API contract.
        .target(
            name: "PropertyLawCore",
            dependencies: []
        ),
        .testTarget(
            name: "PropertyLawCoreTests",
            dependencies: ["PropertyLawCore"]
        ),
        // User-facing macro target — declarations only. Re-exports
        // PropertyLawKit so users importing PropertyLawMacro can call the
        // generated `checkXxxPropertyLaws` functions without a second import.
        .target(
            name: "PropertyLawMacro",
            dependencies: [
                "PropertyLawKit",
                "PropertyLawMacroImpl"
            ]
        ),
        // Compiler-plugin target hosting the macro implementation. Plugin
        // targets compile against swift-syntax and run during macro expansion.
        .macro(
            name: "PropertyLawMacroImpl",
            dependencies: [
                "PropertyLawCore",
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
                .product(name: "SwiftDiagnostics", package: "swift-syntax")
            ]
        ),
        .testTarget(
            name: "PropertyLawMacroTests",
            dependencies: [
                "PropertyLawMacro",
                "PropertyLawMacroImpl",
                "PropertyLawKit",
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
            name: "PropertyLawDiscoveryTool",
            dependencies: [
                "PropertyLawCore",
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax")
            ]
        ),
        .plugin(
            name: "PropertyLawDiscoveryPlugin",
            capability: .command(
                intent: .custom(
                    verb: "propertylawcheck",
                    description: """
                        Generate PropertyLawKit test files by walking a target's source files \
                        and detecting stdlib protocol conformances.
                        """
                ),
                permissions: [
                    .writeToPackageDirectory(reason:
                        "PropertyLawDiscoveryPlugin writes a generated test file (default: " +
                        "Tests/<Target>Tests/PropertyLawTests.generated.swift) listing the " +
                        "checkXxxPropertyLaws calls for each detected conformance."
                    )
                ]
            ),
            dependencies: [
                "PropertyLawDiscoveryTool"
            ]
        ),
        .testTarget(
            name: "PropertyLawDiscoveryToolTests",
            dependencies: [
                "PropertyLawDiscoveryTool",
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax")
            ]
        )
    ]
)
