import PropertyBased

/// Aggregate-mode counterpart to `PerLawDriver` for laws that judge an
/// entire trial budget in one shot rather than per-trial (e.g.
/// `Hashable.distribution`).
///
/// The `PropertyBackend` protocol intentionally doesn't model aggregate
/// laws — both backends would loop identically and report a single
/// pass/fail. Keeping aggregate on the kit side avoids inflating the
/// public protocol's surface for a path with no backend divergence.
internal enum AggregateDriver {

    /// Outcome of an aggregate check. The closure decides pass/fail and
    /// supplies the counterexample inline (it has access to the running
    /// sample set the backend would otherwise need to replay).
    enum Outcome: Sendable {
        case passed
        case failed(counterexample: String)
    }

    static func run(
        protocolLaw: String,
        tier: StrictnessTier,
        options: LawCheckOptions,
        nearMissCollector: NearMissCollector? = nil,
        check: @Sendable (inout Xoshiro, Int) async throws -> Outcome
    ) async -> CheckResult {
        let environment = Environment.current(backend: options.backend)
        if let skip = LawSuppressionPolicy.match(
            protocolLaw: protocolLaw,
            kind: .skip,
            in: options.suppressions
        ) {
            return LawSuppressionPolicy.suppressedResult(
                protocolLaw: protocolLaw,
                tier: tier,
                seed: options.seed,
                environment: environment,
                reason: skip.reason
            )
        }
        var rng = options.seed?.makeXoshiro() ?? Xoshiro()
        let initialSeed = Seed(xoshiro: rng)
        let trials = options.budget.trialCount
        let outcome: CheckResult.Outcome
        do {
            switch try await check(&rng, trials) {
            case .passed:
                outcome = .passed
            case .failed(let counterexample):
                outcome = .failed(counterexample: counterexample)
            }
        } catch {
            outcome = .failed(counterexample: "aggregate check threw: \(error)")
        }
        let raw = CheckResult(
            protocolLaw: protocolLaw,
            tier: tier,
            trials: trials,
            seed: initialSeed,
            environment: environment,
            outcome: outcome,
            nearMisses: nearMissCollector?.snapshot()
        )
        return LawSuppressionPolicy.rewriteIfIntentional(
            raw,
            in: options.suppressions
        )
    }
}
