import ProtoLawCore

/// Cross-file conformance aggregation produced by `ModuleScanner` and
/// consumed by `GeneratedFileEmitter`. Entries are sorted by `typeName`
/// for stable output across runs (PRD §5.3 regeneration-as-diff guarantee).
struct ConformanceMap: Sendable, Equatable {

    struct Provenance: Sendable, Hashable, Comparable {
        /// Path passed to the scanner — typically relative to the package
        /// root when invoked via the plugin, absolute when invoked directly.
        let filePath: String
        let line: Int
        let kind: ProvenanceKind

        static func < (lhs: Provenance, rhs: Provenance) -> Bool {
            if lhs.filePath != rhs.filePath { return lhs.filePath < rhs.filePath }
            if lhs.line != rhs.line { return lhs.line < rhs.line }
            return lhs.kind.rawValue < rhs.kind.rawValue
        }
    }

    enum ProvenanceKind: String, Sendable, Hashable {
        case primary           // struct / class / enum / actor declaration
        case `extension`       // `extension Foo: ...`
    }

    struct Entry: Sendable, Equatable {
        let typeName: String
        /// Most-specific surviving conformances per PRD §4.3 dedupe rule.
        let conformances: Set<KnownProtocol>
        let provenances: [Provenance]
        /// Generator-derivation choice (PRD §5.7) computed at scan time
        /// from the type's kind, inheritance clause, and whether any
        /// declaration in the module supplies `static func gen()`.
        let derivationStrategy: DerivationStrategy
    }

    /// Sorted by `typeName` ascending.
    let entries: [Entry]

    /// Files the scanner couldn't parse — surfaced in the generated
    /// header so the user knows their output is partial.
    let parseFailures: [ParseFailure]

    /// Per-type witness signatures consumed by `AdvisorySuggester`
    /// (PRD §5.4). Keyed by the same `typeName` as `entries`; a missing
    /// key just means "no witnesses recorded" (e.g. extension-only
    /// declarations of stdlib types). Defaults to empty so the existing
    /// emitter call sites (which only need conformances) stay terse.
    let witnesses: [String: WitnessSet]

    struct ParseFailure: Sendable, Equatable {
        let filePath: String
        let message: String
    }

    init(
        entries: [Entry],
        parseFailures: [ParseFailure],
        witnesses: [String: WitnessSet] = [:]
    ) {
        self.entries = entries
        self.parseFailures = parseFailures
        self.witnesses = witnesses
    }
}

/// Structural evidence that a type may want a particular conformance
/// (PRD §5.4 Advisory: missing-conformance suggestions, M4 scope).
///
/// Each flag is set when the corresponding declaration appears in the
/// type's own body or any of its same-module extensions. We deliberately
/// match on signature shape, not full type resolution — false positives
/// are possible but rare for these specific signatures, and the
/// suggester only emits HIGH-confidence advice by default.
struct WitnessSet: Sendable, Equatable {
    /// `static func ==(lhs:rhs:) -> Bool` — Equatable witness.
    var hasEqualEqualOperator: Bool = false
    /// `func hash(into:)` — Hashable witness.
    var hasHashIntoMethod: Bool = false
    /// `static func <(lhs:rhs:) -> Bool` — Comparable witness.
    var hasLessThanOperator: Bool = false
    /// `func encode(to:)` — Encodable half of the Codable pair.
    var hasEncodeToMethod: Bool = false
    /// `init(from:)` — Decodable half of the Codable pair.
    var hasInitFromInitializer: Bool = false

    /// Element-wise OR — used by the scanner to merge witnesses across
    /// primary decl + extensions in any order.
    mutating func merge(_ other: WitnessSet) {
        hasEqualEqualOperator     = hasEqualEqualOperator     || other.hasEqualEqualOperator
        hasHashIntoMethod         = hasHashIntoMethod         || other.hasHashIntoMethod
        hasLessThanOperator       = hasLessThanOperator       || other.hasLessThanOperator
        hasEncodeToMethod         = hasEncodeToMethod         || other.hasEncodeToMethod
        hasInitFromInitializer    = hasInitFromInitializer    || other.hasInitFromInitializer
    }
}
