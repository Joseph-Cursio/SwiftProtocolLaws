import Testing
import PropertyBased
@testable import ProtocolLawKit

/// PRD §8 framework self-test gate. Each test plants a violation and asserts
/// the framework catches it. If any of these regress green-on-buggy, the
/// framework has lost the ability to detect that class of violation and
/// shouldn't be released.
struct PlantedBugDetectionTests {

    // MARK: - Equatable Strict-tier planted bugs

    @Test func detectsAntiReflexiveEquality() async throws {
        await #expect(throws: ProtocolLawViolation.self) {
            try await checkEquatableProtocolLaws(
                for: AntiReflexiveEquatable.self,
                using: Gen<AntiReflexiveEquatable>.antiReflexive(),
                options: LawCheckOptions(budget: .sanity)
            )
        }
    }

    @Test func detectsAsymmetricEquality() async throws {
        let violation = await #expect(throws: ProtocolLawViolation.self) {
            try await checkEquatableProtocolLaws(
                for: PriorityCompareEquatable.self,
                using: Gen<PriorityCompareEquatable>.priorityCompare(),
                options: LawCheckOptions(budget: .standard)
            )
        }
        let laws = violation?.results.map(\.protocolLaw) ?? []
        #expect(
            laws.contains { $0.hasPrefix("Equatable.") },
            "expected an Equatable law violation; got: \(laws)"
        )
    }

    @Test func detectsNonTransitiveEquality() async throws {
        let violation = await #expect(throws: ProtocolLawViolation.self) {
            try await checkEquatableProtocolLaws(
                for: RoundingEquatable.self,
                using: Gen<RoundingEquatable>.rounding(),
                options: LawCheckOptions(budget: .standard)
            )
        }
        let laws = violation?.results.map(\.protocolLaw) ?? []
        #expect(
            laws.contains("Equatable.transitivity") || laws.contains("Equatable.negationConsistency"),
            "expected transitivity (or negation-consistency fallout) on RoundingEquatable; got: \(laws)"
        )
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
                options: LawCheckOptions(budget: .sanity),
                laws: .ownOnly
            )
        }
        let laws = violation?.results.map(\.protocolLaw) ?? []
        #expect(
            laws.contains("Hashable.equalityConsistency"),
            "expected Hashable.equalityConsistency in violation set; got: \(laws)"
        )
    }

    // MARK: - Conventional tier escalation via enforcement: .strict

    @Test func unstableHasherDoesNotThrowByDefault() async throws {
        let results = try await checkHashableProtocolLaws(
            for: UnstableHasher.self,
            using: Gen<UnstableHasher>.unstableHasher(),
            options: LawCheckOptions(budget: .sanity),
            laws: .ownOnly
        )
        let stability = results.first { $0.protocolLaw == "Hashable.stabilityWithinProcess" }
        #expect(stability != nil)
        #expect(
            stability?.isViolation == true,
            "expected stabilityWithinProcess to be reported as a violation even in default mode"
        )
        #expect(stability?.tier == .conventional)
    }

    @Test func unstableHasherThrowsUnderStrictEnforcement() async throws {
        let violation = await #expect(throws: ProtocolLawViolation.self) {
            try await checkHashableProtocolLaws(
                for: UnstableHasher.self,
                using: Gen<UnstableHasher>.unstableHasher(),
                options: LawCheckOptions(budget: .sanity, enforcement: .strict),
                laws: .ownOnly
            )
        }
        let laws = violation?.results.map(\.protocolLaw) ?? []
        #expect(laws.contains("Hashable.stabilityWithinProcess"))
    }

    // MARK: - Heuristic tier: distribution

    @Test func detectsDegenerateHashDistribution() async throws {
        let results = try await checkHashableProtocolLaws(
            for: DegenerateHasher.self,
            using: Gen<DegenerateHasher>.degenerate(),
            options: LawCheckOptions(budget: .sanity),
            laws: .ownOnly
        )
        let distribution = results.first { $0.protocolLaw == "Hashable.distribution" }
        #expect(
            distribution?.isViolation == true,
            "expected DegenerateHasher to violate Hashable.distribution"
        )
        #expect(distribution?.tier == .heuristic)
        #expect(distribution?.counterexample?.contains("unique hashValues") == true)
    }

    // MARK: - Inherited Equatable suite re-collection (laws: .all path)

    @Test func collectsInheritedEquatableViolationsWhenLawsIsAll() async throws {
        let violation = await #expect(throws: ProtocolLawViolation.self) {
            try await checkHashableProtocolLaws(
                for: ReflexivityBreakingHashable.self,
                using: Gen<ReflexivityBreakingHashable>.reflexivityBreaking(),
                options: LawCheckOptions(budget: .sanity),
                laws: .all
            )
        }
        let laws = violation?.results.map(\.protocolLaw) ?? []
        #expect(
            laws.contains("Equatable.reflexivity"),
            "expected the inherited Equatable.reflexivity violation; got: \(laws)"
        )
    }

    // MARK: - Comparable Strict-tier planted bugs

    @Test func detectsAntisymmetryViolation() async throws {
        let violation = await #expect(throws: ProtocolLawViolation.self) {
            try await checkComparableProtocolLaws(
                for: BucketedOrder.self,
                using: Gen<BucketedOrder>.bucketedOrder(),
                options: LawCheckOptions(budget: .standard),
                laws: .ownOnly
            )
        }
        let laws = violation?.results.map(\.protocolLaw) ?? []
        #expect(
            laws.contains("Comparable.antisymmetry"),
            "expected antisymmetry in violation set; got: \(laws)"
        )
    }

    @Test func detectsOperatorConsistencyViolation() async throws {
        let violation = await #expect(throws: ProtocolLawViolation.self) {
            try await checkComparableProtocolLaws(
                for: AlwaysLessThan.self,
                using: Gen<AlwaysLessThan>.alwaysLessThan(),
                options: LawCheckOptions(budget: .sanity),
                laws: .ownOnly
            )
        }
        let laws = violation?.results.map(\.protocolLaw) ?? []
        #expect(
            laws.contains("Comparable.operatorConsistency"),
            "expected operatorConsistency in violation set; got: \(laws)"
        )
    }

    @Test func detectsCyclicOrderTransitivity() async throws {
        let violation = await #expect(throws: ProtocolLawViolation.self) {
            try await checkComparableProtocolLaws(
                for: CyclicOrder.self,
                using: Gen<CyclicOrder>.cyclicOrder(),
                options: LawCheckOptions(budget: .standard),
                laws: .ownOnly
            )
        }
        let laws = violation?.results.map(\.protocolLaw) ?? []
        #expect(laws.isEmpty == false)
        #expect(laws.allSatisfy { $0.hasPrefix("Comparable.") })
    }

    // MARK: - Codable round-trip planted bug + .partial mode

    @Test func detectsDroppingFieldUnderStrictMode() async throws {
        let violation = await #expect(throws: ProtocolLawViolation.self) {
            try await checkCodableProtocolLaws(
                for: DroppingFieldRecord.self,
                using: Gen<DroppingFieldRecord>.droppingFieldRecord(),
                config: CodableLawConfig(mode: .strict, codec: .json),
                options: LawCheckOptions(budget: .sanity, enforcement: .strict)
            )
        }
        let laws = violation?.results.map(\.protocolLaw) ?? []
        #expect(laws.contains("Codable.roundTripFidelity[JSON]"))
    }

    @Test func droppingFieldPassesPartialModeForRetainedFieldOnly() async throws {
        let results = try await checkCodableProtocolLaws(
            for: DroppingFieldRecord.self,
            using: Gen<DroppingFieldRecord>.droppingFieldRecord(),
            config: CodableLawConfig(mode: .partial(fields: [\DroppingFieldRecord.id])),
            options: LawCheckOptions(budget: .sanity)
        )
        #expect(
            !results[0].isViolation,
            "partial mode listing only \\.id should ignore the dropped secret field"
        )
    }

    @Test func droppingFieldFailsPartialModeWhenSecretIsListed() async throws {
        let violation = await #expect(throws: ProtocolLawViolation.self) {
            try await checkCodableProtocolLaws(
                for: DroppingFieldRecord.self,
                using: Gen<DroppingFieldRecord>.droppingFieldRecord(),
                config: CodableLawConfig(mode: .partial(fields: [\DroppingFieldRecord.secret])),
                options: LawCheckOptions(budget: .sanity, enforcement: .strict)
            )
        }
        let laws = violation?.results.map(\.protocolLaw) ?? []
        #expect(laws.contains("Codable.roundTripFidelity[JSON]"))
    }
}
