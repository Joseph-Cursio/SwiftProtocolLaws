import Testing
import PropertyBased
@testable import ProtocolLawKit

@Suite struct EnforcementTests {

    @Test func defaultEnforcementOnlyThrowsOnStrictTier() {
        #expect(EnforcementMode.default.shouldThrow(for: .strict))
        #expect(EnforcementMode.default.shouldThrow(for: .conventional) == false)
        #expect(EnforcementMode.default.shouldThrow(for: .heuristic) == false)
    }

    @Test func strictEnforcementThrowsOnEveryTier() {
        #expect(EnforcementMode.strict.shouldThrow(for: .strict))
        #expect(EnforcementMode.strict.shouldThrow(for: .conventional))
        #expect(EnforcementMode.strict.shouldThrow(for: .heuristic))
    }

    @Test func violationFormatterIncludesPRDDisclaimer() {
        let result = CheckResult(
            protocolLaw: "Equatable.symmetry",
            tier: .strict,
            trials: 5,
            seed: Seed(stateA: 1, stateB: 2, stateC: 3, stateD: 4),
            environment: .current,
            outcome: .failed(counterexample: "x = 1, y = 2; …")
        )
        let text = ViolationFormatter.format(result)
        #expect(text.contains("✗"))
        #expect(text.contains("Equatable.symmetry"))
        #expect(text.contains("Strict"))
        #expect(text.contains("Replay with seed:"))
        #expect(text.contains("Empirical evidence, not a proof."))
    }

    // MARK: - M5: near-miss + coverage rendering

    @Test func formatterRendersNearMissesWhenPresent() {
        let result = CheckResult(
            protocolLaw: "Codable.roundTripFidelity[JSON]",
            tier: .conventional,
            trials: 100,
            seed: Seed(stateA: 0, stateB: 0, stateC: 0, stateD: 0),
            environment: .current,
            outcome: .passed,
            nearMisses: [
                "field whitespaceField: \" abc\" → \"abc\"",
                "field timestamp: ..."
            ]
        )
        let text = ViolationFormatter.format(result)
        #expect(text.contains("Near-misses (2):"))
        #expect(text.contains("field whitespaceField"))
        #expect(text.contains("field timestamp"))
    }

    @Test func formatterRendersEmptyNearMissList() {
        let result = CheckResult(
            protocolLaw: "Codable.roundTripFidelity[JSON]",
            tier: .conventional,
            trials: 100,
            seed: Seed(stateA: 0, stateB: 0, stateC: 0, stateD: 0),
            environment: .current,
            outcome: .passed,
            nearMisses: []
        )
        let text = ViolationFormatter.format(result)
        #expect(text.contains("Near-misses: none."))
    }

    @Test func formatterOmitsNearMissesWhenNil() {
        let result = CheckResult(
            protocolLaw: "Equatable.reflexivity",
            tier: .strict,
            trials: 100,
            seed: Seed(stateA: 0, stateB: 0, stateC: 0, stateD: 0),
            environment: .current,
            outcome: .passed,
            nearMisses: nil
        )
        let text = ViolationFormatter.format(result)
        #expect(text.contains("Near-misses") == false)
    }

    @Test func formatterCapsLongNearMissLists() {
        let result = CheckResult(
            protocolLaw: "X.law",
            tier: .conventional,
            trials: 100,
            seed: Seed(stateA: 0, stateB: 0, stateC: 0, stateD: 0),
            environment: .current,
            outcome: .passed,
            nearMisses: (1...8).map { "entry-\($0)" }
        )
        let text = ViolationFormatter.format(result)
        #expect(text.contains("Near-misses (8):"))
        #expect(text.contains("entry-1"))
        #expect(text.contains("entry-5"))
        #expect(text.contains("… 3 more"))
        #expect(text.contains("entry-6") == false)
    }

    @Test func formatterRendersCoverageHintsSorted() {
        let result = CheckResult(
            protocolLaw: "Equatable.reflexivity",
            tier: .strict,
            trials: 1_000,
            seed: Seed(stateA: 0, stateB: 0, stateC: 0, stateD: 0),
            environment: .current,
            outcome: .passed,
            coverageHints: CoverageHints(
                inputClasses: ["positive": 500, "negative": 488, "zero": 12],
                boundaryHits: ["Int.min": 1, "Int.max": 0]
            )
        )
        let text = ViolationFormatter.format(result)
        #expect(text.contains("Coverage:"))
        // Sorted by key: negative, positive, zero — boundary keys: Int.max, Int.min
        #expect(text.contains("classes={negative: 488, positive: 500, zero: 12}"))
        #expect(text.contains("boundaries={Int.max: 0, Int.min: 1}"))
    }

    @Test func formatterOmitsCoverageWhenNil() {
        let result = CheckResult(
            protocolLaw: "Equatable.reflexivity",
            tier: .strict,
            trials: 100,
            seed: Seed(stateA: 0, stateB: 0, stateC: 0, stateD: 0),
            environment: .current,
            outcome: .passed
        )
        let text = ViolationFormatter.format(result)
        #expect(text.contains("Coverage:") == false)
    }
}
