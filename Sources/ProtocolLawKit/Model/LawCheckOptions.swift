/// Cross-cutting options shared by every `checkXxxProtocolLaws` function.
///
/// Bundled into a struct so the public surface stays small and uniform —
/// `budget`, `enforcement`, `seed`, and `suppressions` are universally
/// meaningful and grow together. Per-protocol concerns (`laws: LawSelection`,
/// Codable's `config: CodableLawConfig`, Sequence's `passing`) remain separate
/// parameters because they vary by check.
public struct LawCheckOptions: Sendable, Hashable {
    public var budget: TrialBudget
    public var enforcement: EnforcementMode
    public var seed: Seed?

    /// Per-call opt-outs (PRD §4.7). Order is irrelevant; the first matching
    /// `LawIdentifier` wins. Suppressions never escalate to a throw, regardless
    /// of `enforcement`.
    public var suppressions: [LawSuppression]

    public init(
        budget: TrialBudget = .standard,
        enforcement: EnforcementMode = .default,
        seed: Seed? = nil,
        suppressions: [LawSuppression] = []
    ) {
        self.budget = budget
        self.enforcement = enforcement
        self.seed = seed
        self.suppressions = suppressions
    }
}
