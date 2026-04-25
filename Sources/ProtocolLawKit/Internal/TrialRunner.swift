import PropertyBased

/// The trial loop that drives a `Generator` through N trials and packages outcomes
/// as a ``CheckResult``. Actor-isolated for the M3+ generator registry; M1 has no
/// shared state across calls but the actor scaffolding stays so later milestones
/// don't have to retrofit isolation onto the call sites.
internal actor TrialRunner {
    enum TrialOutcome: Sendable {
        case pass
        case violation(counterexample: String)
    }

    /// Run `check` once per trial, stopping at the first violation.
    func runPerTrial<T: Sendable, S: SendableSequenceType>(
        protocolLaw: String,
        tier: StrictnessTier,
        trials: Int,
        seed: Seed?,
        generator: Generator<T, S>,
        environment: Environment,
        check: @Sendable (Generator<T, S>, inout Xoshiro) -> TrialOutcome
    ) -> CheckResult {
        var rng = Self.makeRNG(from: seed)
        let initialSeed = Seed(rawValue: rng.currentState)
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

    /// Run `check` once with the full trial budget — for laws like distribution
    /// sanity that judge an aggregate of samples rather than per-trial.
    func runAggregate<T: Sendable, S: SendableSequenceType>(
        protocolLaw: String,
        tier: StrictnessTier,
        trials: Int,
        seed: Seed?,
        generator: Generator<T, S>,
        environment: Environment,
        check: @Sendable (Generator<T, S>, inout Xoshiro, Int) -> TrialOutcome
    ) -> CheckResult {
        var rng = Self.makeRNG(from: seed)
        let initialSeed = Seed(rawValue: rng.currentState)
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

    private static func makeRNG(from seed: Seed?) -> Xoshiro {
        if let seed = seed {
            return Xoshiro(seed: seed.rawValue)
        }
        return Xoshiro()
    }
}
