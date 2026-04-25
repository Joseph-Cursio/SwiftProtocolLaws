public enum LawSelection: Sendable, Hashable {
    /// Run this protocol's own laws plus all inherited protocol law suites (PRD §4.3 default).
    case all

    /// Run only this protocol's own laws; skip inherited suites.
    case ownOnly
}
