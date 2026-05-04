import Testing
import Foundation
import PropertyBased
import PropertyLawKit

/// Pass 2 validation — `Foundation.Decimal`.
///
/// Decimal conforms to `SignedNumeric` (and transitively `Numeric` +
/// `AdditiveArithmetic`) with **exact decimal arithmetic** — unlike
/// `Float` / `Double`, multiplication and addition do not round in the
/// usual IEEE-754 sense for values within Decimal's mantissa precision
/// (38 digits). v1.4 M1's exact-equality algebraic laws should hold
/// cleanly for bounded magnitudes.
///
/// Bounded generator: cube of `1_000` is `1_000_000_000`, well within
/// Decimal's 128-bit mantissa range, so triple multiplication won't lose
/// precision under random sampling.
struct DecimalLawsTests {

    @Test func decimalPassesSignedNumericLaws() async throws {
        try await checkSignedNumericPropertyLaws(
            for: Decimal.self,
            using: Gen<Int>.int(in: -1_000...1_000).map { Decimal($0) },
            options: LawCheckOptions(budget: .standard)
        )
    }

    @Test func decimalPassesNumericLawsOwnOnly() async throws {
        try await checkNumericPropertyLaws(
            for: Decimal.self,
            using: Gen<Int>.int(in: -1_000...1_000).map { Decimal($0) },
            options: LawCheckOptions(budget: .standard),
            laws: .ownOnly
        )
    }

    @Test func decimalPassesAdditiveArithmeticLaws() async throws {
        try await checkAdditiveArithmeticPropertyLaws(
            for: Decimal.self,
            using: Gen<Int>.int(in: -1_000_000...1_000_000).map { Decimal($0) },
            options: LawCheckOptions(budget: .standard)
        )
    }
}
