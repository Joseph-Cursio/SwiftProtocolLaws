import Foundation
import Testing
import PropertyBased
@testable import ProtocolLawKit

@Suite struct NearMissTests {

    // MARK: - Codable .semantic mode records field-level diffs as near-misses

    @Test func semanticRoundTripRecordsFieldDiffsAsNearMisses() async throws {
        // SemanticDriftRecord's `whitespaceField` round-trips with a leading
        // space stripped. Under `.semantic` equivalence we ignore that — but
        // the field-level diff should surface on `nearMisses`.
        let results = try await checkCodableProtocolLaws(
            for: SemanticDriftRecord.self,
            using: Gen<SemanticDriftRecord>.semanticDrift(),
            config: CodableLawConfig(
                mode: .semantic { lhs, rhs in
                    lhs.id == rhs.id
                        && lhs.whitespaceField.trimmingCharacters(in: .whitespaces)
                            == rhs.whitespaceField.trimmingCharacters(in: .whitespaces)
                }
            ),
            options: LawCheckOptions(budget: .sanity)
        )
        let result = try #require(results.first)
        // Law passes via semantic equivalence.
        #expect(result.outcome == .passed)
        // Near-miss collector populated; mentions the whitespace field.
        let nearMisses = try #require(result.nearMisses)
        #expect(!nearMisses.isEmpty, "expected at least one field diff")
        #expect(
            nearMisses.contains { $0.contains("whitespaceField") },
            "expected whitespaceField diff; got: \(nearMisses)"
        )
    }

    // MARK: - Codable .partial mode records non-listed-field diffs as near-misses

    @Test func partialRoundTripRecordsUnlistedFieldDiffs() async throws {
        // SemanticDriftRecord drops the leading space on whitespaceField. Under
        // `.partial` listing only `id`, the law passes but the whitespaceField
        // diff is a near-miss the reviewer should see.
        let results = try await checkCodableProtocolLaws(
            for: SemanticDriftRecord.self,
            using: Gen<SemanticDriftRecord>.semanticDrift(),
            config: CodableLawConfig(mode: .partial(fields: [\SemanticDriftRecord.id])),
            options: LawCheckOptions(budget: .sanity)
        )
        let result = try #require(results.first)
        #expect(result.outcome == .passed)
        let nearMisses = try #require(result.nearMisses)
        #expect(
            nearMisses.contains { $0.contains("whitespaceField") },
            "expected whitespaceField diff in near-misses; got: \(nearMisses)"
        )
    }

    // MARK: - Codable .strict mode does NOT track field-level near-misses

    @Test func strictModeReportsNilNearMisses() async throws {
        // .strict mode treats any field diff as a violation. There are no
        // "near-misses" in that mode by design — `nearMisses` stays nil to
        // preserve the §4.6 "this law doesn't track near-misses" semantic.
        let results = try await checkCodableProtocolLaws(
            for: Int.self,
            using: TestGen.smallInt(),
            config: CodableLawConfig(mode: .strict),
            options: LawCheckOptions(budget: .sanity)
        )
        let result = try #require(results.first)
        #expect(result.outcome == .passed)
        #expect(result.nearMisses == nil)
    }

    // MARK: - Clean run with no diffs reports an empty near-miss list, not nil

    @Test func cleanSemanticRunReportsEmptyNearMisses() async throws {
        // Int round-trips perfectly; `.semantic` accepts it and the mirror
        // walk finds no field diffs. nearMisses should be `[]`, not nil —
        // the collector ran but found nothing.
        let results = try await checkCodableProtocolLaws(
            for: Int.self,
            using: TestGen.smallInt(),
            config: CodableLawConfig(mode: .semantic { $0 == $1 }),
            options: LawCheckOptions(budget: .sanity)
        )
        let result = try #require(results.first)
        #expect(result.outcome == .passed)
        #expect(result.nearMisses == [])
    }
}

// MARK: - Test fixtures

/// Codable record whose `whitespaceField` is round-tripped through a custom
/// init that strips the leading whitespace. Under `.strict` this is a
/// violation; under `.semantic` (with a trim-aware predicate) or `.partial`
/// (listing only `id`) the law passes — but the per-field diff should surface
/// as a near-miss.
struct SemanticDriftRecord: Codable, Equatable, Sendable, CustomStringConvertible {
    let id: Int
    let whitespaceField: String

    init(id: Int, whitespaceField: String) {
        self.id = id
        self.whitespaceField = whitespaceField
    }

    enum CodingKeys: String, CodingKey { case id, whitespaceField }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(Int.self, forKey: .id)
        let raw = try container.decode(String.self, forKey: .whitespaceField)
        // The lossy step: strip a leading space if present.
        self.whitespaceField = raw.hasPrefix(" ") ? String(raw.dropFirst()) : raw
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(whitespaceField, forKey: .whitespaceField)
    }

    var description: String { "SDR(\(id), \"\(whitespaceField)\")" }
}

extension Gen where Value == SemanticDriftRecord {
    static func semanticDrift() -> Generator<SemanticDriftRecord, some SendableSequenceType> {
        // Always prefix the field with a space so the lossy decode is
        // exercised on every trial.
        zip(Gen<Int>.int(in: 0...100), Gen<Character>.letterOrNumber.string(of: 1...4))
            .map { id, suffix in
                SemanticDriftRecord(id: id, whitespaceField: " \(suffix)")
            }
    }
}
