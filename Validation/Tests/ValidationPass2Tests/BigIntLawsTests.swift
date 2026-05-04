import Testing
import PropertyBased
import PropertyLawKit
import BigInt

/// Pass 2 validation — `attaswift/BigInt`.
///
/// `BigInt` and `BigUInt` are the only types in the Swift ecosystem outside
/// stdlib that fully conform to the integer chain (BinaryInteger /
/// SignedInteger / UnsignedInteger / Numeric / SignedNumeric /
/// AdditiveArithmetic) with **exact arithmetic**. Implementing 2's complement
/// bitwise / shift / division on top of `[Word]`-backed storage is non-
/// trivial — this is the first property-based test of the package's
/// protocol conformance against an external law suite.
///
/// Bounded generators are still useful: BigInt multiplication doesn't
/// overflow but it does *grow* (digit-count multiplies on each multiply),
/// so unbounded ranges would slow `.standard` runs without adding signal.
struct BigIntLawsTests {

    // MARK: - BigInt (signed arbitrary-precision)

    @Test func bigIntPassesBinaryIntegerLaws() async throws {
        try await checkBinaryIntegerPropertyLaws(
            for: BigInt.self,
            using: Gen<Int>.int(in: -1_000_000...1_000_000).map { BigInt($0) },
            options: LawCheckOptions(budget: .standard)
        )
    }

    @Test func bigIntPassesSignedIntegerLaws() async throws {
        try await checkSignedIntegerPropertyLaws(
            for: BigInt.self,
            using: Gen<Int>.int(in: -1_000_000...1_000_000).map { BigInt($0) },
            options: LawCheckOptions(budget: .standard)
        )
    }

    // MARK: - BigUInt (unsigned arbitrary-precision)

    /// Suppressions for laws that depend on a consistent bit-width and don't
    /// hold on arbitrary-precision unsigned types. `BigUInt.~` flips bits
    /// across the underlying word array, so `~0` is `0` (zero-word storage)
    /// while `~x` for non-zero `x` flips a full word — De Morgan and
    /// double-negation fail because the LHS and RHS have different storage
    /// sizes after the flip.
    ///
    /// `BigInt` (signed) is unaffected: `~x = -(x+1)` is an arithmetic
    /// identity that doesn't depend on storage. The bigInt* tests above
    /// pass without suppressions.
    private static let arbitraryPrecisionBitwiseSuppressions: [LawSuppression] = [
        .intentionalViolation(
            LawIdentifier(protocolName: "BinaryInteger", lawName: "bitwiseDoubleNegation"),
            reason: "BigUInt: ~x storage-size depends on x's word count, so ~~x != x"
        ),
        .intentionalViolation(
            LawIdentifier(protocolName: "BinaryInteger", lawName: "bitwiseDeMorgan"),
            reason: "BigUInt: ~ has no consistent bit-width for arbitrary-precision unsigned"
        )
    ]

    @Test func bigUIntPassesBinaryIntegerLaws() async throws {
        try await checkBinaryIntegerPropertyLaws(
            for: BigUInt.self,
            using: Gen<UInt>.uint(in: 0...1_000_000).map { BigUInt($0) },
            options: LawCheckOptions(
                budget: .standard,
                suppressions: Self.arbitraryPrecisionBitwiseSuppressions
            )
        )
    }

    @Test func bigUIntPassesUnsignedIntegerLaws() async throws {
        try await checkUnsignedIntegerPropertyLaws(
            for: BigUInt.self,
            using: Gen<UInt>.uint(in: 0...1_000_000).map { BigUInt($0) },
            options: LawCheckOptions(
                budget: .standard,
                suppressions: Self.arbitraryPrecisionBitwiseSuppressions
            )
        )
    }
}
