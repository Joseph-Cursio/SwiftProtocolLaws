/// Cross-cutting options shared by every `checkXxxProtocolLaws` function.
///
/// Bundled into a struct so the public surface stays small and uniform —
/// `budget`, `enforcement`, `seed`, `suppressions`, `backend`, and the
/// replay-validation pair are universally meaningful and grow together.
/// Per-protocol concerns (`laws: LawSelection`, Codable's
/// `config: CodableLawConfig`, Sequence's `passing`) remain separate
/// parameters because they vary by check.
///
/// Not `Hashable` — the `backend: any PropertyBackend` field is an existential,
/// and forcing every backend implementation to be `Hashable` would foreclose
/// reasonable backends. Tests that compare options compare field-by-field.
public struct LawCheckOptions: Sendable {
    public var budget: TrialBudget
    public var enforcement: EnforcementMode
    public var seed: Seed?

    /// Per-call opt-outs (PRD §4.7). Order is irrelevant; the first matching
    /// `LawIdentifier` wins. Suppressions never escalate to a throw, regardless
    /// of `enforcement`.
    public var suppressions: [LawSuppression]

    /// Property-based backend that drives the per-trial loop (PRD §4.5).
    /// Default is `SwiftPropertyBasedBackend`. Swap in `SwiftQCBackend` to
    /// route the kit's law checks through SwiftQC; aggregate-mode laws
    /// (`Hashable.distribution`) bypass the backend.
    public var backend: any PropertyBackend

    /// When non-nil, the kit verifies this fingerprint matches
    /// `Environment.current(backend:)` before running and throws
    /// `ReplayEnvironmentMismatch` on divergence (PRD §4.6). Pair with
    /// `seed` when replaying a stored CI artifact.
    public var expectedReplayEnvironment: Environment?

    /// Strictness applied to `expectedReplayEnvironment` matching. Default
    /// is `.exact`; relaxations exist for legitimate toolchain bumps.
    public var replayRelaxation: EnvironmentRelaxation

    public init(
        budget: TrialBudget = .standard,
        enforcement: EnforcementMode = .default,
        seed: Seed? = nil,
        suppressions: [LawSuppression] = [],
        backend: any PropertyBackend = SwiftPropertyBasedBackend(),
        expectedReplayEnvironment: Environment? = nil,
        replayRelaxation: EnvironmentRelaxation = .exact
    ) {
        self.budget = budget
        self.enforcement = enforcement
        self.seed = seed
        self.suppressions = suppressions
        self.backend = backend
        self.expectedReplayEnvironment = expectedReplayEnvironment
        self.replayRelaxation = replayRelaxation
    }
}
