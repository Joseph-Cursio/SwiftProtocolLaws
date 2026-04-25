import PropertyBased

/// Drives a `Generator` through N trials and packages outcomes as
/// ``CheckResult``. Each instance is bound to a single `(generator, seed,
/// trials, environment)` configuration; per-law method calls only need the
/// law's name, tier, and check closure.
///
/// Actor-isolated for the M3+ generator registry; M1 has no shared state
/// across calls but the actor scaffolding stays so later milestones don't
/// have to retrofit isolation onto the call sites.
internal actor TrialRunner<Value: Sendable, Shrinker: SendableSequenceType> {
    private let trials: Int
    private let seed: Seed?
    private let generator: Generator<Value, Shrinker>
    private let environment: Environment

    init(
        trials: Int,
        seed: Seed?,
        generator: Generator<Value, Shrinker>,
        environment: Environment
    ) {
        self.trials = trials
        self.seed = seed
        self.generator = generator
        self.environment = environment
    }

    /// Run `check` once per trial, stopping at the first violation.
    func runPerTrial(
        protocolLaw: String,
        tier: StrictnessTier,
        check: @Sendable (Generator<Value, Shrinker>, inout Xoshiro) -> TrialOutcome
    ) -> CheckResult {
        var rng = makeRNG()
        let initialSeed = Seed(xoshiro: rng)
        var ranTrials = 0
        for _ in 0..<trials {
            ranTrials += 1
            switch check(generator, &rng) {
            case .pass:
                continue
            case .violation(let counter):
                return CheckResult(
                    protocolLaw: protocolLaw,
                    tier: tier,
                    trials: ranTrials,
                    seed: initialSeed,
                    environment: environment,
                    outcome: .failed(counterexample: counter)
                )
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
        var rng = makeRNG()
        let initialSeed = Seed(xoshiro: rng)
        let outcome: CheckResult.Outcome
        switch check(generator, &rng, trials) {
        case .pass:
            outcome = .passed
        case .violation(let counter):
            outcome = .failed(counterexample: counter)
        }
        return CheckResult(
            protocolLaw: protocolLaw,
            tier: tier,
            trials: trials,
            seed: initialSeed,
            environment: environment,
            outcome: outcome
        )
    }

    private func makeRNG() -> Xoshiro {
        seed?.makeXoshiro() ?? Xoshiro()
    }
}
