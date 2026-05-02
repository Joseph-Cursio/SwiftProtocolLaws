import Testing
import PropertyBased
@testable import ProtocolLawKit

struct GroupLawsTests {

    // Positive control — `AdditiveInt` (`(Int, +, 0, -)`) is the canonical
    // additive group: addition is associative, 0 is two-sided identity,
    // negation is two-sided inverse.
    @Test func additiveIntPassesAllFiveLaws() async throws {
        let results = try await checkGroupProtocolLaws(
            for: AdditiveInt.self,
            using: AdditiveInt.gen(),
            options: LawCheckOptions(budget: .sanity)
        )
        for result in results {
            #expect(result.isViolation == false, "\(result.protocolLaw) should pass for AdditiveInt")
        }
        // 1 inherited Semigroup + 2 inherited Monoid + 2 own Group = 5.
        #expect(results.count == 5)
    }

    @Test func ownOnlySkipsInheritedLaws() async throws {
        let results = try await checkGroupProtocolLaws(
            for: AdditiveInt.self,
            using: AdditiveInt.gen(),
            options: LawCheckOptions(budget: .sanity),
            laws: .ownOnly
        )
        #expect(results.count == 2)
        let names = Set(results.map(\.protocolLaw))
        #expect(names == [
            "Group.combineLeftInverse",
            "Group.combineRightInverse"
        ])
    }

    @Test func tiersAreReportedAsStrict() async throws {
        let results = try await checkGroupProtocolLaws(
            for: AdditiveInt.self,
            using: AdditiveInt.gen(),
            options: LawCheckOptions(budget: .sanity)
        )
        #expect(results.allSatisfy { $0.tier == .strict })
    }

    @Test func lawNamesMatchPRD() async throws {
        let results = try await checkGroupProtocolLaws(
            for: AdditiveInt.self,
            using: AdditiveInt.gen(),
            options: LawCheckOptions(budget: .sanity)
        )
        let names = Set(results.map(\.protocolLaw))
        #expect(names == [
            "Semigroup.combineAssociativity",
            "Monoid.combineLeftIdentity",
            "Monoid.combineRightIdentity",
            "Group.combineLeftInverse",
            "Group.combineRightInverse"
        ])
    }

    // Negative control — `BrokenInverse` returns `x` for `inverse(x)`
    // (identity instead of inverse). The own-only check surfaces both
    // inverse violations; `.default` enforcement throws.
    @Test func brokenInverseFailsBothInverseLaws() async throws {
        await #expect(throws: ProtocolLawViolation.self) {
            try await checkGroupProtocolLaws(
                for: BrokenInverse.self,
                using: BrokenInverse.gen(),
                options: LawCheckOptions(budget: .sanity),
                laws: .ownOnly
            )
        }
    }
}

/// Test fixture: `Int`-wrapping `Group` whose `combine` is addition,
/// `identity` is 0, and `inverse(x)` is `-x`. Positive control across
/// the Group suite — the canonical additive group of integers.
struct AdditiveInt: Group, Equatable, Sendable, CustomStringConvertible {
    let value: Int

    static let identity = AdditiveInt(value: 0)

    static func combine(_ lhs: AdditiveInt, _ rhs: AdditiveInt) -> AdditiveInt {
        AdditiveInt(value: lhs.value &+ rhs.value)
    }

    static func inverse(_ x: AdditiveInt) -> AdditiveInt {
        AdditiveInt(value: 0 &- x.value)
    }

    var description: String { "AInt(\(value))" }
}

extension AdditiveInt {
    static func gen() -> Generator<AdditiveInt, some SendableSequenceType> {
        // Bounded range avoids the &+ wraparound from masking inverse-law
        // failures on overflow; ±100 keeps the per-trial arithmetic exact.
        Gen<Int>.int(in: -100...100).map { AdditiveInt(value: $0) }
    }
}

/// Negative control — `inverse(x) = x` is wrong (the identity function
/// is only an inverse when x is itself the identity). Used in the
/// `brokenInverseFailsBothInverseLaws` test to confirm the
/// Group inverse laws fire the Strict violation they should.
struct BrokenInverse: Group, Equatable, Sendable, CustomStringConvertible {
    let value: Int

    static let identity = BrokenInverse(value: 0)

    static func combine(_ lhs: BrokenInverse, _ rhs: BrokenInverse) -> BrokenInverse {
        BrokenInverse(value: lhs.value &+ rhs.value)
    }

    static func inverse(_ x: BrokenInverse) -> BrokenInverse {
        // Wrong on purpose — should be `-x.value`, not `x.value`.
        BrokenInverse(value: x.value)
    }

    var description: String { "BI(\(value))" }
}

extension BrokenInverse {
    static func gen() -> Generator<BrokenInverse, some SendableSequenceType> {
        // Generator skips 0 so every sample exposes the broken-inverse bug
        // (0's inverse IS 0, so x=0 wouldn't fail the law).
        Gen<Int>.int(in: 1...100).map { BrokenInverse(value: $0) }
    }
}
