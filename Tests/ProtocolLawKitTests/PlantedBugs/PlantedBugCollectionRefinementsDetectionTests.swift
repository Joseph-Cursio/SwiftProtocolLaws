import Testing
import PropertyBased
@testable import ProtocolLawKit

/// PRD §8 framework self-test gate, collection-refinements cluster
/// (BidirectionalCollection, RandomAccessCollection, MutableCollection,
/// RangeReplaceableCollection). Split from `PlantedBugCollectionsDetectionTests`
/// so neither suite breaches SwiftLint's type-body length limit.
struct PlantedBugRefinementsDetectionTests {

    // MARK: - BidirectionalCollection Strict-tier planted bug

    @Test func detectsStuckIndexBeforeViolation() async throws {
        let violation = await #expect(throws: ProtocolLawViolation.self) {
            try await checkBidirectionalCollectionProtocolLaws(
                for: StuckIndexBeforeCollection.self,
                using: Gen<StuckIndexBeforeCollection>.stuckIndexBefore(),
                options: LawCheckOptions(budget: .sanity),
                laws: .ownOnly
            )
        }
        let laws = violation?.results.map(\.protocolLaw) ?? []
        let bidiLaws = Set(laws).intersection([
            "BidirectionalCollection.indexBeforeAfterRoundTrip",
            "BidirectionalCollection.indexAfterBeforeRoundTrip",
            "BidirectionalCollection.reverseTraversalConsistency"
        ])
        #expect(
            !bidiLaws.isEmpty,
            "expected at least one bidirectional law to fire; got: \(laws)"
        )
    }

    // MARK: - RandomAccessCollection Strict-tier planted bug

    @Test func detectsWrongDistanceViolation() async throws {
        let violation = await #expect(throws: ProtocolLawViolation.self) {
            try await checkRandomAccessCollectionProtocolLaws(
                for: WrongDistanceCollection.self,
                using: Gen<WrongDistanceCollection>.wrongDistance(),
                options: LawCheckOptions(budget: .sanity),
                laws: .ownOnly
            )
        }
        let laws = violation?.results.map(\.protocolLaw) ?? []
        #expect(
            laws.contains("RandomAccessCollection.distanceConsistency"),
            "expected distanceConsistency; got: \(laws)"
        )
    }

    // MARK: - MutableCollection Strict-tier planted bug

    @Test func detectsNoOpSetterViolation() async throws {
        let violation = await #expect(throws: ProtocolLawViolation.self) {
            try await checkMutableCollectionProtocolLaws(
                for: NoOpSetterCollection.self,
                using: Gen<NoOpSetterCollection>.noOpSetter(),
                options: LawCheckOptions(budget: .sanity),
                laws: .ownOnly
            )
        }
        let laws = violation?.results.map(\.protocolLaw) ?? []
        #expect(
            laws.contains("MutableCollection.swapAtSwapsValues"),
            "expected swapAtSwapsValues; got: \(laws)"
        )
    }

    // MARK: - RangeReplaceableCollection Strict-tier planted bug

    @Test func detectsNoOpReplaceSubrangeViolation() async throws {
        let violation = await #expect(throws: ProtocolLawViolation.self) {
            try await checkRangeReplaceableCollectionProtocolLaws(
                for: NoOpReplaceSubrange.self,
                using: Gen<NoOpReplaceSubrange>.noOpReplaceSubrange(),
                options: LawCheckOptions(budget: .sanity),
                laws: .ownOnly
            )
        }
        let laws = violation?.results.map(\.protocolLaw) ?? []
        #expect(
            laws.contains("RangeReplaceableCollection.replaceSubrangeAppliesEdit"),
            "expected replaceSubrangeAppliesEdit; got: \(laws)"
        )
    }
}
