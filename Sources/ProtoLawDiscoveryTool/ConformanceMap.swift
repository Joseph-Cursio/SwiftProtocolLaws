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
    }

    /// Sorted by `typeName` ascending.
    let entries: [Entry]

    /// Files the scanner couldn't parse — surfaced in the generated
    /// header so the user knows their output is partial.
    let parseFailures: [ParseFailure]

    struct ParseFailure: Sendable, Equatable {
        let filePath: String
        let message: String
    }
}
