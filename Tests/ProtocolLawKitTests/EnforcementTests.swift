import Testing
import PropertyBased
@testable import ProtocolLawKit

@Suite struct EnforcementTests {

    @Test func defaultEnforcementOnlyThrowsOnStrictTier() {
        #expect(EnforcementMode.default.shouldThrow(for: .strict))
        #expect(!EnforcementMode.default.shouldThrow(for: .conventional))
        #expect(!EnforcementMode.default.shouldThrow(for: .heuristic))
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
            seed: Seed(rawValue: (1, 2, 3, 4)),
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
}
