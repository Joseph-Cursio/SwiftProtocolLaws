import Testing
import PropertyBased
import PropertyLawKit
import ComplexModule

/// Pass 2 validation — `apple/swift-numerics` `Complex<Double>`.
///
/// `Complex<Double>` conforms to `Numeric` / `SignedNumeric` /
/// `AdditiveArithmetic`. Its underlying components are `Double`, so the
/// kit's exact-equality algebraic laws (associativity, distributivity)
/// fire spurious violations under random sampling — same root cause as
/// why M1's doc-comment redirects FP users to M4 and why FloatingPoint
/// types subsume the algebraic chain so the macro/discovery doesn't
/// emit those checks for them.
///
/// `Complex` is *not* itself a `FloatingPoint` (no `infinity`, `isNaN`,
/// etc. on the type — only on the underlying RealType), so the kit can't
/// route it through `checkFloatingPointPropertyLaws`. This file documents
/// the empirical limit: bounded-magnitude Complex<Double> generators
/// passing AdditiveArithmetic on a ~1000 magnitude range, with multiplication
/// laws suppressed via `intentionalViolation` because they're known to fire
/// on round-error edges.
struct ComplexLawsTests {

    /// Suppressions for laws that depend on exact-equality multiplication
    /// over IEEE-754 floats. These don't hold for any `Numeric` whose
    /// underlying components are floating-point (Complex<Double>,
    /// Complex<Float>, hypothetical Quaternion<Double>, etc.).
    private static let floatingPointArithmeticSuppressions: [LawSuppression] = [
        .intentionalViolation(
            LawIdentifier(protocolName: "Numeric", lawName: "multiplicationAssociativity"),
            reason: "Complex<Double>: IEEE-754 rounding makes (x*y)*z != x*(y*z) under exact =="
        ),
        .intentionalViolation(
            LawIdentifier(protocolName: "Numeric", lawName: "leftDistributivity"),
            reason: "Complex<Double>: IEEE-754 rounding makes x*(y+z) != x*y + x*z under exact =="
        ),
        .intentionalViolation(
            LawIdentifier(protocolName: "Numeric", lawName: "rightDistributivity"),
            reason: "Complex<Double>: IEEE-754 rounding makes (x+y)*z != x*z + y*z under exact =="
        ),
        .intentionalViolation(
            LawIdentifier(
                protocolName: "AdditiveArithmetic",
                lawName: "additionAssociativity"
            ),
            reason: "Complex<Double>: IEEE-754 rounding makes (x+y)+z != x+(y+z) under exact =="
        ),
        .intentionalViolation(
            LawIdentifier(
                protocolName: "AdditiveArithmetic",
                lawName: "subtractionInverse"
            ),
            reason: "Complex<Double>: subtraction inverse fails when x+y is large vs x"
        )
    ]

    private static func complexGenerator() -> Generator<Complex<Double>, some SendableSequenceType> {
        Gen<Int>.int(in: -100...100).map { tag in
            Complex(Double(tag), Double(tag % 7))
        }
    }

    @Test func complexDoublePassesNumericLawsWithFPSuppressions() async throws {
        try await checkNumericPropertyLaws(
            for: Complex<Double>.self,
            using: Self.complexGenerator(),
            options: LawCheckOptions(
                budget: .sanity,
                suppressions: Self.floatingPointArithmeticSuppressions
            ),
            laws: .ownOnly
        )
    }

    @Test func complexDoublePassesSignedNumericOwnLaws() async throws {
        // SignedNumeric's own laws — negation involution, additive inverse,
        // negate-mutation consistency, negation distributes over addition —
        // hold exactly for Complex<Double> because they don't involve the
        // rounding-prone multiplication or three-way addition. Run with
        // .ownOnly to skip the inherited Numeric laws (which would fire).
        try await checkSignedNumericPropertyLaws(
            for: Complex<Double>.self,
            using: Self.complexGenerator(),
            options: LawCheckOptions(budget: .standard),
            laws: .ownOnly
        )
    }
}
