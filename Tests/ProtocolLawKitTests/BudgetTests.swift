import Testing
import PropertyBased
@testable import ProtocolLawKit

@Suite struct BudgetTests {

    @Test func sanityRuns100Trials() async throws {
        let results = try await checkEquatableProtocolLaws(
            for: Int.self,
            using: TestGen.smallInt(),
            budget: .sanity
        )
        for result in results where !result.isViolation {
            #expect(result.trials == 100)
        }
    }

    @Test func standardRuns1000Trials() async throws {
        let results = try await checkEquatableProtocolLaws(
            for: Int.self,
            using: TestGen.smallInt(),
            budget: .standard
        )
        for result in results where !result.isViolation {
            #expect(result.trials == 1_000)
        }
    }

    @Test func customRunsRequestedTrials() async throws {
        let results = try await checkEquatableProtocolLaws(
            for: Int.self,
            using: TestGen.smallInt(),
            budget: .custom(trials: 250)
        )
        for result in results where !result.isViolation {
            #expect(result.trials == 250)
        }
    }

    @Test func exhaustiveDefaultsTo10kButCanBeOverridden() async throws {
        let results = try await checkEquatableProtocolLaws(
            for: Int.self,
            using: TestGen.smallInt(),
            budget: .exhaustive(500) // override to keep this test fast
        )
        for result in results where !result.isViolation {
            #expect(result.trials == 500)
        }
        #expect(TrialBudget.exhaustive().trialCount == 10_000)
    }
}
