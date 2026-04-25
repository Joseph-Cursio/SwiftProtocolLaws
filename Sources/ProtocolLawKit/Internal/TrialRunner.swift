import PropertyBased

/// Drives a `Generator` through N trials and packages outcomes as
/// ``CheckResult``. Each instance is bound to a single
/// `(generator, seed, trials, environment, suppressions)` configuration; per-law
/// method calls only need the law's name, tier, and check closure.
///
/// Actor-isolated for the M3+ generator registry; M1 has no shared state
/// across calls but the actor scaffolding stays so later milestones don't
/// have to retrofit isolation onto the call sites.
internal actor TrialRunner<Value: Sendable, Shrinker: SendableSequenceType> {
    private let trials: Int
    private let seed: Seed?
    private let generator: Generator<Value, Shrinker>
    private let environment: Environment
    private let suppressions: [LawSuppression]

    init(
        trials: Int,
        seed: Seed?,
        generator: Generator<Value, Shrinker>,
        environment: Environment,
        suppressions: [LawSuppression] = []
    ) {
        self.trials = trials
        self.seed = seed
        self.generator = generator
        self.environment = environment
        self.suppressions = suppressions
    }

    /// Run `check` once per trial, stopping at the first violation. Honors
    /// `LawSuppression` (PRD §4.7) — `.skip` returns a `.suppressed` result
    /// without paying the trial budget; `.intentionalViolation` rewrites a
    /// failing outcome to `.expectedViolation`.
    func runPerTrial(
        protocolLaw: String,
        tier: StrictnessTier,
        check: @Sendable (Generator<Value, Shrinker>, inout Xoshiro) -> TrialOutcome
    ) -> CheckResult {
        if let skip = suppressionMatch(for: protocolLaw, kind: .skip) {
            return suppressedResult(protocolLaw: protocolLaw, tier: tier, reason: skip.reason)
        }
        var rng = makeRNG()
        let initialSeed = Seed(xoshiro: rng)
        var ranTrials = 0
        for _ in 0..<trials {
            ranTrials += 1
            switch check(generator, &rng) {
            case .pass:
                continue
            case .violation(let counter):
                let raw = CheckResult(
                    protocolLaw: protocolLaw,
                    tier: tier,
                    trials: ranTrials,
                    seed: initialSeed,
                    environment: environment,
                    outcome: .failed(counterexample: counter)
                )
                return rewriteIfIntentional(raw)
            }
        }
        return CheckResult(
            protocolLaw: protocolLaw,
            tier: tier,
            trials: ranTrials,
            seed: initialSeed,
            environment: environment,
            outcome: .passed
        )
    }

    /// Run `check` once with the full trial budget — for laws that judge an
    /// aggregate of samples (distribution sanity, etc.) rather than per-trial.
    func runAggregate(
        protocolLaw: String,
        tier: StrictnessTier,
        check: @Sendable (Generator<Value, Shrinker>, inout Xoshiro, Int) -> TrialOutcome
    ) -> CheckResult {
        if let skip = suppressionMatch(for: protocolLaw, kind: .skip) {
            return suppressedResult(protocolLaw: protocolLaw, tier: tier, reason: skip.reason)
        }
        var rng = makeRNG()
        let initialSeed = Seed(xoshiro: rng)
        let outcome: CheckResult.Outcome
        switch check(generator, &rng, trials) {
        case .pass:
            outcome = .passed
        case .violation(let counter):
            outcome = .failed(counterexample: counter)
        }
        let raw = CheckResult(
            protocolLaw: protocolLaw,
            tier: tier,
            trials: trials,
            seed: initialSeed,
            environment: environment,
            outcome: outcome
        )
        return rewriteIfIntentional(raw)
    }

    private func makeRNG() -> Xoshiro {
        seed?.makeXoshiro() ?? Xoshiro()
    }

    private func suppressionMatch(
        for protocolLaw: String,
        kind: LawSuppression.Kind
    ) -> LawSuppression? {
        suppressions.first { $0.identifier.matches(protocolLaw) && $0.kind == kind }
    }

    private func suppressedResult(
        protocolLaw: String,
        tier: StrictnessTier,
        reason: String
    ) -> CheckResult {
        // No RNG was consumed; preserve any caller-provided seed so re-runs of
        // the same options stay deterministic.
        let resolvedSeed = seed ?? Seed(stateA: 0, stateB: 0, stateC: 0, stateD: 0)
        return CheckResult(
            protocolLaw: protocolLaw,
            tier: tier,
            trials: 0,
            seed: resolvedSeed,
            environment: environment,
            outcome: .suppressed(reason: reason)
        )
    }

    private func rewriteIfIntentional(_ raw: CheckResult) -> CheckResult {
        guard case .failed(let counterexample) = raw.outcome else { return raw }
        guard let intent = suppressionMatch(
            for: raw.protocolLaw,
            kind: .intentionalViolation
        ) else { return raw }
        return CheckResult(
            protocolLaw: raw.protocolLaw,
            tier: raw.tier,
            trials: raw.trials,
            seed: raw.seed,
            environment: raw.environment,
            outcome: .expectedViolation(reason: intent.reason, counterexample: counterexample),
            nearMisses: raw.nearMisses,
            coverageHints: raw.coverageHints
        )
    }
}
