import Testing
import PropertyBased
@testable import ProtocolLawKit

/// PRD §8 framework self-test gate. Each test plants a violation and asserts
/// the framework catches it. If any of these regress green-on-buggy, the
/// framework has lost the ability to detect that class of violation and
/// shouldn't be released.
@Suite struct PlantedBugDetectionTests {

    // MARK: - Equatable Strict-tier planted bugs

    @Test func detectsAntiReflexiveEquality() async throws {
        await #expect(throws: ProtocolLawViolation.self) {
            try await checkEquatableProtocolLaws(
                for: AntiReflexiveEquatable.self,
                using: Gen<AntiReflexiveEquatable>.antiReflexive(),
                budget: .sanity
            )
        }
    }

    @Test func detectsAsymmetricEquality() async throws {
        let violation = await #expect(throws: ProtocolLawViolation.self) {
            try await checkEquatableProtocolLaws(
                for: PriorityCompareEquatable.self,
                using: Gen<PriorityCompareEquatable>.priorityCompare(),
                budget: .standard
            )
        }
        let laws = violation?.results.map(\.protocolLaw) ?? []
        // Should detect at least one of: reflexivity (priority == priority returns false unless reflexive trick),
        // symmetry, transitivity, or negationConsistency.
        #expect(laws.contains { $0.hasPrefix("Equatable.") },
                "expected an Equatable law violation; got: \(laws)")
    }

    @Test func detectsNonTransitiveEquality() async throws {
        let violation = await #expect(throws: ProtocolLawViolation.self) {
            try await checkEquatableProtocolLaws(
                for: RoundingEquatable.self,
                using: Gen<RoundingEquatable>.rounding(),
                budget: .standard
            )
        }
        let laws = violation?.results.map(\.protocolLaw) ?? []
        #expect(laws.contains("Equatable.transitivity") || laws.contains("Equatable.negationConsistency"),
                "expected transitivity (or negation-consistency fallout) on RoundingEquatable; got: \(laws)")
    }

    // Note: Equatable.negationConsistency is structurally unviolable in Swift
    // (see PlantedEquatableViolators.swift), so there is no planted-bug test
    // for it. The framework still runs the check as defensive documentation.

    // MARK: - Hashable Strict-tier planted bug

    @Test func detectsHashEqualityInconsistency() async throws {
        let violation = await #expect(throws: ProtocolLawViolation.self) {
            try await checkHashableProtocolLaws(
                for: EqualButDifferentHash.self,
                using: Gen<EqualButDifferentHash>.equalButDifferentHash(),
                budget: .sanity,
                laws: .ownOnly
            )
        }
        let laws = violation?.results.map(\.protocolLaw) ?? []
        #expect(laws.contains("Hashable.equalityConsistency"),
                "expected Hashable.equalityConsistency in violation set; got: \(laws)")
    }

    // MARK: - Conventional tier escalation via enforcement: .strict

    @Test func unstableHasherDoesNotThrowByDefault() async throws {
        // stabilityWithinProcess is Conventional — default enforcement records
        // the violation but does not throw.
        let results = try await checkHashableProtocolLaws(
            for: UnstableHasher.self,
            using: Gen<UnstableHasher>.unstableHasher(),
            budget: .sanity,
            laws: .ownOnly
        )
        let stability = results.first { $0.protocolLaw == "Hashable.stabilityWithinProcess" }
        #expect(stability != nil)
        #expect(stability?.isViolation == true,
                "expected stabilityWithinProcess to be reported as a violation even in default mode")
        #expect(stability?.tier == .conventional)
    }

    @Test func unstableHasherThrowsUnderStrictEnforcement() async throws {
        let violation = await #expect(throws: ProtocolLawViolation.self) {
            try await checkHashableProtocolLaws(
                for: UnstableHasher.self,
                using: Gen<UnstableHasher>.unstableHasher(),
                budget: .sanity,
                enforcement: .strict,
                laws: .ownOnly
            )
        }
        let laws = violation?.results.map(\.protocolLaw) ?? []
        #expect(laws.contains("Hashable.stabilityWithinProcess"))
    }

    // MARK: - Heuristic tier: distribution

    @Test func detectsDegenerateHashDistribution() async throws {
        // Heuristic tier — does not throw under default enforcement.
        let results = try await checkHashableProtocolLaws(
            for: DegenerateHasher.self,
            using: Gen<DegenerateHasher>.degenerate(),
            budget: .sanity,
            laws: .ownOnly
        )
        let distribution = results.first { $0.protocolLaw == "Hashable.distribution" }
        #expect(distribution?.isViolation == true,
                "expected DegenerateHasher to violate Hashable.distribution")
        #expect(distribution?.tier == .heuristic)
        #expect(distribution?.counterexample?.contains("unique hashValues") == true)
    }

    // MARK: - Inherited Equatable suite re-collection (laws: .all path)

    @Test func collectsInheritedEquatableViolationsWhenLawsIsAll() async throws {
        // When laws == .all, checkHashableProtocolLaws runs the Equatable
        // suite first. If Equatable throws, the catch branch re-collects its
        // results so the final report reflects every violated law.
        let violation = await #expect(throws: ProtocolLawViolation.self) {
            try await checkHashableProtocolLaws(
                for: ReflexivityBreakingHashable.self,
                using: Gen<ReflexivityBreakingHashable>.reflexivityBreaking(),
                budget: .sanity,
                laws: .all
            )
        }
        let laws = violation?.results.map(\.protocolLaw) ?? []
        #expect(laws.contains("Equatable.reflexivity"),
                "expected the inherited Equatable.reflexivity violation in the report; got: \(laws)")
    }
}
