/// Sequence-specific configuration (PRD §4.3 Sequence).
///
/// `Sequence` does not require multi-pass iteration in general — sequences
/// that document themselves as single-pass (e.g. `AnyIterator` wrappers,
/// network streams) pass `.singlePass` to suppress the multi-pass and
/// `makeIterator()`-independence checks.
public struct SequenceLawOptions: Sendable, Hashable {
    public enum Passing: Sendable, Hashable {
        case multiPass
        case singlePass
    }

    public var passing: Passing

    public init(passing: Passing = .multiPass) {
        self.passing = passing
    }
}
