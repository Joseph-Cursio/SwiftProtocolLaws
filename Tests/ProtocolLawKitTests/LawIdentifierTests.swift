import Testing
@testable import ProtocolLawKit

/// Coverage + regression suite for `LawIdentifier` and the per-protocol
/// law enums (`EquatableLaw`, `HashableLaw`, ..., `SetAlgebraLaw`).
///
/// These enums double as the type-safe entry points to suppression
/// (`LawIdentifier.setAlgebra(.unionIdempotence)`). They have to stay in
/// sync with the runtime law constants emitted by `checkXxxProtocolLaws`
/// — if a law gets added to one side but not the other, suppression
/// silently fails for that law and tests would still pass without these
/// regression guards.
///
/// The `*EnumCoversRuntimeLaws` tests assert the enum's `allCases` covers
/// every law name the corresponding `checkXxxProtocolLaws` actually
/// produces. The original miss that motivated this suite: PRD v0.3 added
/// four `symmetricDifference*` laws to `SetAlgebraLaws.swift` but did not
/// extend `SetAlgebraLaw`, so callers had to fall back to the un-typesafe
/// `LawIdentifier(protocolName:lawName:)` initializer.
struct LawIdentifierTests {

    // MARK: - Factory methods produce well-formed qualified names

    @Test func equatableFactoryProducesCorrectQualifiedNames() {
        for law in EquatableLaw.allCases {
            let id = LawIdentifier.equatable(law)
            #expect(id.protocolName == "Equatable")
            #expect(id.lawName == law.rawValue)
            #expect(id.qualifiedName == "Equatable.\(law.rawValue)")
        }
    }

    @Test func hashableFactoryProducesCorrectQualifiedNames() {
        for law in HashableLaw.allCases {
            let id = LawIdentifier.hashable(law)
            #expect(id.qualifiedName == "Hashable.\(law.rawValue)")
        }
    }

    @Test func comparableFactoryProducesCorrectQualifiedNames() {
        for law in ComparableLaw.allCases {
            let id = LawIdentifier.comparable(law)
            #expect(id.qualifiedName == "Comparable.\(law.rawValue)")
        }
    }

    @Test func codableFactoryProducesCorrectQualifiedNames() {
        for law in CodableLaw.allCases {
            let id = LawIdentifier.codable(law)
            #expect(id.qualifiedName == "Codable.\(law.rawValue)")
        }
    }

    @Test func iteratorProtocolFactoryProducesCorrectQualifiedNames() {
        for law in IteratorProtocolLaw.allCases {
            let id = LawIdentifier.iteratorProtocol(law)
            #expect(id.qualifiedName == "IteratorProtocol.\(law.rawValue)")
        }
    }

    @Test func sequenceFactoryProducesCorrectQualifiedNames() {
        for law in SequenceLaw.allCases {
            let id = LawIdentifier.sequence(law)
            #expect(id.qualifiedName == "Sequence.\(law.rawValue)")
        }
    }

    @Test func collectionFactoryProducesCorrectQualifiedNames() {
        for law in CollectionLaw.allCases {
            let id = LawIdentifier.collection(law)
            #expect(id.qualifiedName == "Collection.\(law.rawValue)")
        }
    }

    @Test func setAlgebraFactoryProducesCorrectQualifiedNames() {
        for law in SetAlgebraLaw.allCases {
            let id = LawIdentifier.setAlgebra(law)
            #expect(id.qualifiedName == "SetAlgebra.\(law.rawValue)")
        }
    }

    // MARK: - Enums cover every runtime law name (anti-divergence guards)

    /// The motivating case for this suite: PRD v0.3 added four
    /// `symmetricDifference*` laws to `SetAlgebraLaws.swift` but `SetAlgebraLaw`
    /// initially missed them. This test asserts the enum's `allCases`
    /// covers every Strict-tier SetAlgebra law name the runtime emits.
    @Test func setAlgebraEnumCoversRuntimeLaws() async throws {
        let results = try await checkSetAlgebraProtocolLaws(
            for: Set<Int>.self,
            using: Gen<Int>.int(in: 0...20).array(of: 0...3).map(Set.init),
            options: LawCheckOptions(budget: .sanity)
        )
        let runtimeLaws = Set(results.map(\.protocolLaw))
        let enumLaws = Set(SetAlgebraLaw.allCases.map { "SetAlgebra.\($0.rawValue)" })
        let missing = runtimeLaws.subtracting(enumLaws)
        #expect(
            missing.isEmpty,
            "SetAlgebraLaw enum is missing cases for: \(missing.sorted().joined(separator: ", "))"
        )
    }

    @Test func equatableEnumCoversRuntimeLaws() async throws {
        let results = try await checkEquatableProtocolLaws(
            for: Int.self,
            using: Gen<Int>.int(in: 0...20),
            options: LawCheckOptions(budget: .sanity)
        )
        let runtimeLaws = Set(results.map(\.protocolLaw))
        let enumLaws = Set(EquatableLaw.allCases.map { "Equatable.\($0.rawValue)" })
        #expect(runtimeLaws.subtracting(enumLaws).isEmpty)
    }

    @Test func hashableEnumCoversRuntimeLaws() async throws {
        let results = try await checkHashableProtocolLaws(
            for: Int.self,
            using: Gen<Int>.int(in: 0...20),
            options: LawCheckOptions(budget: .sanity),
            laws: .ownOnly
        )
        let runtimeLaws = Set(results.map(\.protocolLaw))
        let enumLaws = Set(HashableLaw.allCases.map { "Hashable.\($0.rawValue)" })
        #expect(runtimeLaws.subtracting(enumLaws).isEmpty)
    }

    @Test func comparableEnumCoversRuntimeLaws() async throws {
        let results = try await checkComparableProtocolLaws(
            for: Int.self,
            using: Gen<Int>.int(in: 0...20),
            options: LawCheckOptions(budget: .sanity),
            laws: .ownOnly
        )
        let runtimeLaws = Set(results.map(\.protocolLaw))
        let enumLaws = Set(ComparableLaw.allCases.map { "Comparable.\($0.rawValue)" })
        #expect(runtimeLaws.subtracting(enumLaws).isEmpty)
    }

    // MARK: - LawIdentifier Hashable conformance is well-behaved

    @Test func lawIdentifierIsUsableAsSetElement() {
        let ids: Set<LawIdentifier> = [
            .equatable(.reflexivity),
            .equatable(.reflexivity), // duplicate — Set should dedupe
            .hashable(.equalityConsistency),
            .setAlgebra(.symmetricDifferenceDefinition)
        ]
        #expect(ids.count == 3)
        #expect(ids.contains(.equatable(.reflexivity)))
        #expect(ids.contains(.equatable(.symmetry)) == false)
    }

    @Test func lawIdentifierEqualityIsByValue() {
        let lhs = LawIdentifier(protocolName: "Equatable", lawName: "reflexivity")
        let rhs = LawIdentifier.equatable(.reflexivity)
        #expect(lhs == rhs)
        #expect(lhs.hashValue == rhs.hashValue)
    }
}
