import Testing
import PropertyBased
@testable import PropertyLawKit

struct BudgetTests {

    @Test func sanityRuns100Trials() async throws {
        let results = try await checkEquatablePropertyLaws(
            for: Int.self,
            using: TestGen.smallInt(),
            options: LawCheckOptions(budget: .sanity)
        )
        let nonViolations = results.filter { !$0.isViolation }
        try #require(nonViolations.isEmpty == false)
        for result in nonViolations {
            #expect(result.trials == 100)
        }
    }

    @Test func standardRuns1000Trials() async throws {
        let results = try await checkEquatablePropertyLaws(
            for: Int.self,
            using: TestGen.smallInt(),
            options: LawCheckOptions(budget: .standard)
        )
        let nonViolations = results.filter { !$0.isViolation }
        try #require(nonViolations.isEmpty == false)
        for result in nonViolations {
            #expect(result.trials == 1_000)
        }
    }

    @Test func customRunsRequestedTrials() async throws {
        let results = try await checkEquatablePropertyLaws(
            for: Int.self,
            using: TestGen.smallInt(),
            options: LawCheckOptions(budget: .custom(trials: 250))
        )
        let nonViolations = results.filter { !$0.isViolation }
        try #require(nonViolations.isEmpty == false)
        for result in nonViolations {
            #expect(result.trials == 250)
        }
    }

    @Test func exhaustiveDefaultsTo10kButCanBeOverridden() async throws {
        let results = try await checkEquatablePropertyLaws(
            for: Int.self,
            using: TestGen.smallInt(),
            options: LawCheckOptions(budget: .exhaustive(500))
        )
        let nonViolations = results.filter { !$0.isViolation }
        try #require(nonViolations.isEmpty == false)
        for result in nonViolations {
            #expect(result.trials == 500)
        }
        #expect(TrialBudget.exhaustive().trialCount == 10_000)
    }
}
