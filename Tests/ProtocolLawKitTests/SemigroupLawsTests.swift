import Testing
import PropertyBased
@testable import ProtocolLawKit

struct SemigroupLawsTests {

    // Positive control — `String` under concatenation is the canonical
    // free semigroup. Concat is associative for any string inputs.
    @Test func stringConcatenationPassesAssociativity() async throws {
        let results = try await checkSemigroupProtocolLaws(
            for: StringMonoid.self,
            using: StringMonoid.gen(),
            options: LawCheckOptions(budget: .sanity)
        )
        for result in results {
            #expect(result.isViolation == false, "\(result.protocolLaw) should pass for StringMonoid")
        }
        #expect(results.count == 1)
    }

    @Test func tierIsReportedAsStrict() async throws {
        let results = try await checkSemigroupProtocolLaws(
            for: StringMonoid.self,
            using: StringMonoid.gen(),
            options: LawCheckOptions(budget: .sanity)
        )
        #expect(results.allSatisfy { $0.tier == .strict })
    }

    @Test func lawNameMatchesPRD() async throws {
        let results = try await checkSemigroupProtocolLaws(
            for: StringMonoid.self,
            using: StringMonoid.gen(),
            options: LawCheckOptions(budget: .sanity)
        )
        let names = Set(results.map(\.protocolLaw))
        #expect(names == ["Semigroup.combineAssociativity"])
    }
}

/// Test fixture: `String`-wrapping `Semigroup` whose `combine` is the
/// canonical concatenation. Used as a positive control across both
/// Semigroup and Monoid suites.
struct StringMonoid: Semigroup, Equatable, Sendable, CustomStringConvertible {
    let value: String

    static func combine(_ lhs: StringMonoid, _ rhs: StringMonoid) -> StringMonoid {
        StringMonoid(value: lhs.value + rhs.value)
    }

    var description: String { "SM(\(value))" }
}

extension StringMonoid {
    static func gen() -> Generator<StringMonoid, some SendableSequenceType> {
        Gen<Character>.letterOrNumber.string(of: 0...4).map { StringMonoid(value: $0) }
    }
}
