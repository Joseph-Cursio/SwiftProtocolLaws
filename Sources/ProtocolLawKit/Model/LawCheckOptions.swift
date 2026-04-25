/// Cross-cutting options shared by every `checkXxxProtocolLaws` function.
///
/// Bundled into a struct so the public surface stays small and uniform —
/// `budget`, `enforcement`, and `seed` are universally meaningful and grow
/// together. Per-protocol concerns (`laws: LawSelection`, Codable's
/// `config: CodableLawConfig`) remain separate parameters because they vary
/// by check.
public struct LawCheckOptions: Sendable, Hashable {
    public var budget: TrialBudget
    public var enforcement: EnforcementMode
    public var seed: Seed?

    public init(
        budget: TrialBudget = .standard,
        enforcement: EnforcementMode = .default,
        seed: Seed? = nil
    ) {
        self.budget = budget
        self.enforcement = enforcement
        self.seed = seed
    }
}
