import PropertyBased

/// Bundles the three closures every per-law check needs — keeps
/// `PerLawDriver.run` under the function-parameter-count lint without
/// inflating individual call sites.
internal struct LawCheck<Input: Sendable>: Sendable {
    let sample: @Sendable (inout Xoshiro) -> Input
    let property: @Sendable (Input) async throws -> Bool
    let formatCounterexample: @Sendable (Input, ErrorBox?) -> String
}

/// Replaces M1's `TrialRunner` for per-trial laws. Sits between every public
/// `checkXxxProtocolLaws` entry point and the chosen `PropertyBackend`,
/// owning the policy bits the backend itself doesn't (suppression rewriting,
/// `CheckResult` assembly, environment fingerprinting).
internal enum PerLawDriver {

    /// Run a per-trial law against `options.backend`, package the outcome as
    /// a `CheckResult`, and apply any matching suppression.
    static func run<Input: Sendable>(
        protocolLaw: String,
        tier: StrictnessTier,
        options: LawCheckOptions,
        check: LawCheck<Input>
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
        let backendResult = await options.backend.check(
            trials: options.budget.trialCount,
            seed: options.seed,
            sample: check.sample,
            property: check.property
        )
        let raw = packageResult(
            protocolLaw: protocolLaw,
            tier: tier,
            environment: environment,
            backendResult: backendResult,
            formatCounterexample: check.formatCounterexample
        )
        return LawSuppressionPolicy.rewriteIfIntentional(
            raw,
            in: options.suppressions
        )
    }

    private static func packageResult<Input: Sendable>(
        protocolLaw: String,
        tier: StrictnessTier,
        environment: Environment,
        backendResult: BackendCheckResult<Input>,
        formatCounterexample: (Input, ErrorBox?) -> String
    ) -> CheckResult {
        switch backendResult {
        case .passed(let trialsRun, let initialSeed):
            return CheckResult(
                protocolLaw: protocolLaw,
                tier: tier,
                trials: trialsRun,
                seed: initialSeed,
                environment: environment,
                outcome: .passed
            )
        case .failed(let trialsRun, let initialSeed, let failingInput, let thrownError):
            let counterexample = formatCounterexample(failingInput, thrownError)
            return CheckResult(
                protocolLaw: protocolLaw,
                tier: tier,
                trials: trialsRun,
                seed: initialSeed,
                environment: environment,
                outcome: .failed(counterexample: counterexample)
            )
        }
    }
}
