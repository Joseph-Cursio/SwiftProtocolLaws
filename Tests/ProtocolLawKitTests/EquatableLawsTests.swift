import Testing
import PropertyBased
@testable import ProtocolLawKit

@Suite struct EquatableLawsTests {

    @Test func intsPassAllStrictLaws() async throws {
        let results = try await checkEquatableProtocolLaws(
            for: Int.self,
            using: TestGen.smallInt(),
            budget: .sanity
        )
        #expect(results.count == 4)
        for result in results {
            #expect(!result.isViolation, "\(result.protocolLaw) should pass for Int — got: \(result.counterexample ?? "<no counter>")")
            #expect(result.tier == .strict)
        }
    }

    @Test func stringsPassAllStrictLaws() async throws {
        let results = try await checkEquatableProtocolLaws(
            for: String.self,
            using: TestGen.smallString(),
            budget: .sanity
        )
        #expect(results.count == 4)
        for result in results {
            #expect(!result.isViolation, "\(result.protocolLaw) should pass for String")
        }
    }

    @Test func customStructPassesAllStrictLaws() async throws {
        let results = try await checkEquatableProtocolLaws(
            for: Coordinate.self,
            using: Gen<Coordinate>.coordinate(),
            budget: .sanity
        )
        #expect(results.count == 4)
        for result in results {
            #expect(!result.isViolation, "\(result.protocolLaw) should pass for Coordinate")
        }
    }

    @Test func resultsCarryReplayableSeed() async throws {
        let results = try await checkEquatableProtocolLaws(
            for: Int.self,
            using: TestGen.smallInt(),
            budget: .sanity,
            seed: Seed(rawValue: (1, 2, 3, 4))
        )
        #expect(!results.isEmpty)
        for result in results {
            // The seed in each result is the rng state captured before that
            // law's first pump — we passed (1,2,3,4) so each law's seed is (1,2,3,4).
            #expect(result.seed == Seed(rawValue: (1, 2, 3, 4)))
            #expect(result.environment.backendIdentity == "swift-property-based")
        }
    }

    @Test func eachLawCarriesItsOwnAttributableName() async throws {
        let results = try await checkEquatableProtocolLaws(
            for: Int.self,
            using: TestGen.smallInt(),
            budget: .sanity
        )
        let laws = Set(results.map(\.protocolLaw))
        #expect(laws == [
            "Equatable.reflexivity",
            "Equatable.symmetry",
            "Equatable.transitivity",
            "Equatable.negationConsistency"
        ])
    }
}
