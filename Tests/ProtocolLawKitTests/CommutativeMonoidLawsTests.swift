import Testing
import PropertyBased
@testable import ProtocolLawKit

struct CommutativeMonoidLawsTests {

    // Positive control — `Tally` (`(Int, +, 0)`) is the canonical
    // commutative monoid: addition is commutative, associative, has 0
    // as two-sided identity.
    @Test func tallyPassesAllFourLaws() async throws {
        let results = try await checkCommutativeMonoidProtocolLaws(
            for: Tally.self,
            using: Tally.gen(),
            options: LawCheckOptions(budget: .sanity)
        )
        for result in results {
            #expect(result.isViolation == false, "\(result.protocolLaw) should pass for Tally")
        }
        // 1 inherited Semigroup + 2 inherited Monoid + 1 own CommutativeMonoid = 4.
        #expect(results.count == 4)
    }

    @Test func ownOnlySkipsInheritedLaws() async throws {
        let results = try await checkCommutativeMonoidProtocolLaws(
            for: Tally.self,
            using: Tally.gen(),
            options: LawCheckOptions(budget: .sanity),
            laws: .ownOnly
        )
        #expect(results.count == 1)
        let names = Set(results.map(\.protocolLaw))
        #expect(names == ["CommutativeMonoid.combineCommutativity"])
    }

    @Test func tiersAreReportedAsStrict() async throws {
        let results = try await checkCommutativeMonoidProtocolLaws(
            for: Tally.self,
            using: Tally.gen(),
            options: LawCheckOptions(budget: .sanity)
        )
        #expect(results.allSatisfy { $0.tier == .strict })
    }

    @Test func lawNamesMatchPRD() async throws {
        let results = try await checkCommutativeMonoidProtocolLaws(
            for: Tally.self,
            using: Tally.gen(),
            options: LawCheckOptions(budget: .sanity)
        )
        let names = Set(results.map(\.protocolLaw))
        #expect(names == [
            "Semigroup.combineAssociativity",
            "Monoid.combineLeftIdentity",
            "Monoid.combineRightIdentity",
            "CommutativeMonoid.combineCommutativity"
        ])
    }

    // Negative control — `StringMonoid` (string concat) is a Monoid
    // but NOT commutative: `"a" + "b" != "b" + "a"`. The own-only check
    // surfaces the violation; `.default` enforcement throws.
    @Test func stringConcatFailsCommutativity() async throws {
        await #expect(throws: ProtocolLawViolation.self) {
            try await checkCommutativeMonoidProtocolLaws(
                for: NonCommutativeString.self,
                using: NonCommutativeString.gen(),
                options: LawCheckOptions(budget: .sanity),
                laws: .ownOnly
            )
        }
    }
}

/// Test fixture: `Int`-wrapping `CommutativeMonoid` whose `combine` is
/// addition and `identity` is 0. Positive control across the
/// CommutativeMonoid suite.
struct Tally: CommutativeMonoid, Equatable, Sendable, CustomStringConvertible {
    let count: Int

    static let identity = Tally(count: 0)

    static func combine(_ lhs: Tally, _ rhs: Tally) -> Tally {
        Tally(count: lhs.count &+ rhs.count)
    }

    var description: String { "Tally(\(count))" }
}

extension Tally {
    static func gen() -> Generator<Tally, some SendableSequenceType> {
        Gen<Int>.int(in: -100...100).map { Tally(count: $0) }
    }
}

/// Negative control — string concatenation is associative + has identity
/// (empty string) but is NOT commutative. Used in the
/// `stringConcatFailsCommutativity` test to confirm the
/// CommutativeMonoid law fires the Strict violation it should.
///
/// Defined here rather than reusing `StringMonoid` so the negative
/// control's intent is unambiguous in the test name.
struct NonCommutativeString: CommutativeMonoid, Equatable, Sendable, CustomStringConvertible {
    let value: String

    static let identity = NonCommutativeString(value: "")

    static func combine(
        _ lhs: NonCommutativeString,
        _ rhs: NonCommutativeString
    ) -> NonCommutativeString {
        NonCommutativeString(value: lhs.value + rhs.value)
    }

    var description: String { "NCS(\(value))" }
}

extension NonCommutativeString {
    static func gen() -> Generator<NonCommutativeString, some SendableSequenceType> {
        Gen<Character>.letterOrNumber.string(of: 1...4).map { NonCommutativeString(value: $0) }
    }
}
