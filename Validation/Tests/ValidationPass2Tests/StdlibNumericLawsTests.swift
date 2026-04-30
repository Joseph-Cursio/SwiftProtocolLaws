import Testing
import PropertyBased
import ProtocolLawKit

/// Pass 2 validation (PRD §8) — v1.4 numeric/integer/FloatingPoint
/// expansion. First time the kit's own laws run end-to-end against
/// stdlib types via the validation harness.
///
/// `Int32`, `UInt`, and `Double` are the canonical stdlib reference
/// implementations of FixedWidthInteger + SignedInteger,
/// FixedWidthInteger + UnsignedInteger, and BinaryFloatingPoint
/// respectively. These tests don't expect to find conformance bugs in
/// stdlib (Apple's most heavily-tested numeric implementations) — they
/// document that the kit composes against stdlib and provides a smoke
/// test against the v1.4 cluster.
struct StdlibNumericLawsTests {

    // MARK: - Int32 (FixedWidthInteger + SignedInteger siblings)

    @Test func int32PassesFixedWidthIntegerLaws() async throws {
        try await checkFixedWidthIntegerProtocolLaws(
            for: Int32.self,
            using: Gen<Int32>.boundedForArithmetic(),
            options: LawCheckOptions(budget: .standard)
        )
    }

    @Test func int32PassesSignedIntegerLaws() async throws {
        try await checkSignedIntegerProtocolLaws(
            for: Int32.self,
            using: Gen<Int32>.boundedForArithmetic(),
            options: LawCheckOptions(budget: .standard)
        )
    }

    // MARK: - UInt (FixedWidthInteger + UnsignedInteger siblings)

    @Test func uintPassesFixedWidthIntegerLaws() async throws {
        try await checkFixedWidthIntegerProtocolLaws(
            for: UInt.self,
            using: Gen<UInt>.boundedForArithmetic(),
            options: LawCheckOptions(budget: .standard)
        )
    }

    @Test func uintPassesUnsignedIntegerLaws() async throws {
        try await checkUnsignedIntegerProtocolLaws(
            for: UInt.self,
            using: Gen<UInt>.boundedForArithmetic(),
            options: LawCheckOptions(budget: .standard)
        )
    }

    // MARK: - Double (BinaryFloatingPoint)

    @Test func doublePassesBinaryFloatingPointLawsFinite() async throws {
        try await checkBinaryFloatingPointProtocolLaws(
            for: Double.self,
            using: Gen<Double>.double(in: -1_000_000.0 ... 1_000_000.0),
            options: LawCheckOptions(budget: .standard)
        )
    }

    @Test func doublePassesBinaryFloatingPointLawsWithNaN() async throws {
        try await checkBinaryFloatingPointProtocolLaws(
            for: Double.self,
            using: Gen<Double>.doubleWithNaN(),
            options: LawCheckOptions(budget: .standard, allowNaN: true)
        )
    }
}
