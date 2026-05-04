// swift-tools-version: 6.1
import PackageDescription

/// Validation harness (PRD §8): wires `PropertyLawKit` against external
/// Swift packages and runs actual law checks. Lives in its own SwiftPM
/// package so the external deps don't leak into the kit's main manifest —
/// consumers of SwiftPropertyLaws never see ArgumentParser or Collections.
///
/// Run with:
///   cd Validation && swift test
///
/// **Pass 2** (`ValidationPass2Tests`) — exercises the kit against
/// `swift-argument-parser` (1.6.0+) public types. Demonstrates the
/// pipeline composes: kit + external SwiftPM dep + generators + assertions
/// all link and run end-to-end.
///
/// **Pass 3** (`ValidationPass3Tests`) — retroactive validation against a
/// real bug. `swift-collections` is pinned to revision `8e5e4a8f`
/// (the parent of `35349601`, which fixed `_Bitmap.symmetricDifference`
/// to use `^` instead of `&`). At that SHA, `TreeSet.symmetricDifference`
/// returns the *intersection* rather than the symmetric difference. The
/// pass-3 tests assert that `checkSetAlgebraPropertyLaws` catches the
/// violation via the four `symmetricDifference*` laws added to PRD §4.3
/// SetAlgebra in response to this finding. Counts toward the §8 1.0 gate.
let package = Package(
    name: "Validation",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(name: "SwiftPropertyLaws", path: ".."),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.6.0"),
        // attaswift/BigInt — arbitrary-precision integers conforming to
        // BinaryInteger / SignedInteger / UnsignedInteger / Numeric. v1.4
        // M2's exact-arithmetic algebraic laws should hold cleanly here;
        // first ever property-based test of BigInt's protocol conformance.
        .package(url: "https://github.com/attaswift/BigInt.git", from: "5.5.0"),
        // apple/swift-numerics — exposes Complex<RealType> conforming to
        // Numeric / SignedNumeric. Complex<Double> multiplication is
        // non-associative under exact equality due to IEEE-754 rounding;
        // tests document that boundary explicitly.
        .package(url: "https://github.com/apple/swift-numerics.git", from: "1.0.0"),
        // Pin to the parent of 35349601 — the buggy SHA where
        // `_Bitmap.symmetricDifference` used `&` (intersection) instead
        // of `^` (xor). DO NOT update without re-validating Pass 3:
        // a newer revision has the bug fixed and the pass-3 assertion
        // (kit catches violation) would invert.
        .package(
            url: "https://github.com/apple/swift-collections.git",
            revision: "8e5e4a8f3617283b556064574651fc0869943c9a"
        )
    ],
    targets: [
        .testTarget(
            name: "ValidationPass2Tests",
            dependencies: [
                // PropertyLawKit re-exports PropertyBased (`@_exported import`),
                // so a direct dep on it isn't needed here.
                .product(name: "PropertyLawKit", package: "SwiftPropertyLaws"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "BigInt", package: "BigInt"),
                .product(name: "ComplexModule", package: "swift-numerics")
            ]
        ),
        .testTarget(
            name: "ValidationPass3Tests",
            dependencies: [
                .product(name: "PropertyLawKit", package: "SwiftPropertyLaws"),
                .product(name: "HashTreeCollections", package: "swift-collections")
            ]
        )
    ]
)
