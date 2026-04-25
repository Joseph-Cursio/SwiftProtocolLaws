/// Per-trial result of a single law check. Independent of the runner's
/// generic parameters so helper functions outside `TrialRunner` (Codable's
/// mode-comparison helpers, etc.) can return it without a phony type.
internal enum TrialOutcome: Sendable {
    case pass
    case violation(counterexample: String)
}
