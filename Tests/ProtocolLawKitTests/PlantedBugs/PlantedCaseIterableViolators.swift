import PropertyBased

/// Violates CaseIterable.exactlyOnce. The allCases getter is hand-rolled
/// (compiler can't synthesize on a struct), and it lists `.alpha` twice —
/// the canonical "duplicate case in allCases" failure mode.
struct DuplicatingCases: CaseIterable, Hashable, Sendable, CustomStringConvertible {
    let label: String

    static var allCases: [DuplicatingCases] {
        [
            DuplicatingCases(label: "alpha"),
            DuplicatingCases(label: "beta"),
            DuplicatingCases(label: "alpha")
        ]
    }

    var description: String { "DC(\(label))" }
}

extension Gen where Value == DuplicatingCases {
    static func duplicatingCases() -> Generator<DuplicatingCases, some SendableSequenceType> {
        Gen<DuplicatingCases?>.element(of: DuplicatingCases.allCases).compactMap { $0 }
    }
}
