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
/// `checkXxxPropertyLaws` entry point and the chosen `PropertyBackend`,
/// owning the policy bits the backend itself doesn't (suppression rewriting,
/// `CheckResult` assembly, environment fingerprinting, near-miss snapshot,
/// coverage accumulation).
internal enum PerLawDriver {

    /// Per-law observation hooks (PRD §4.6 confidence reporting). Kept in a
    /// single struct so the `run` signature stays under the
    /// function-parameter-count lint.
    struct Observation<Input: Sendable>: Sendable {
        let nearMissCollector: NearMissCollector?
        let classify: (@Sendable (Input) -> (classes: Set<String>, boundaries: Set<String>))?

        init(
            nearMissCollector: NearMissCollector? = nil,
            classify: (@Sendable (Input) -> (classes: Set<String>, boundaries: Set<String>))? = nil
        ) {
            self.nearMissCollector = nearMissCollector
            self.classify = classify
        }
    }

    /// Run a per-trial law against `options.backend`, package the outcome as
    /// a `CheckResult`, and apply any matching suppression. When
    /// `observation.nearMissCollector` or `observation.classify` are non-nil,
    /// their snapshots are packaged into `CheckResult.nearMisses` /
    /// `coverageHints`; otherwise those fields stay `nil` to preserve the
    /// PRD §4.6 "this law doesn't track" contract.
    static func run<Input: Sendable>(
        protocolLaw: String,
        tier: StrictnessTier,
        options: LawCheckOptions,
        check: LawCheck<Input>,
        observation: Observation<Input> = Observation()
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
        let coverageAccumulator: CoverageAccumulator? = observation.classify == nil
            ? nil
            : CoverageAccumulator()
        let wrappedProperty = wrapProperty(
            check.property,
            classify: observation.classify,
            into: coverageAccumulator
        )
        let backendResult = await options.backend.check(
            trials: options.budget.trialCount,
            seed: options.seed,
            sample: check.sample,
            property: wrappedProperty
        )
        let observed = ObservedSnapshots(
            nearMisses: observation.nearMissCollector?.snapshot(),
            coverageHints: coverageAccumulator?.snapshot()
        )
        let metadata = ResultMetadata(
            protocolLaw: protocolLaw,
            tier: tier,
            environment: environment
        )
        let raw = packageResult(
            metadata: metadata,
            backendResult: backendResult,
            formatCounterexample: check.formatCounterexample,
            observed: observed
        )
        return LawSuppressionPolicy.rewriteIfIntentional(
            raw,
            in: options.suppressions
        )
    }

    private static func wrapProperty<Input: Sendable>(
        _ property: @Sendable @escaping (Input) async throws -> Bool,
        classify: (@Sendable (Input) -> (classes: Set<String>, boundaries: Set<String>))?,
        into accumulator: CoverageAccumulator?
    ) -> @Sendable (Input) async throws -> Bool {
        guard let classify, let accumulator else { return property }
        return { input in
            let (classes, boundaries) = classify(input)
            accumulator.record(classes: classes, boundaries: boundaries)
            return try await property(input)
        }
    }

    /// Packaged observation snapshots for inclusion in the final
    /// `CheckResult`. Bundling keeps `packageResult` under the
    /// function-parameter-count lint while preserving the §4.6 nil/empty
    /// distinction.
    private struct ObservedSnapshots {
        let nearMisses: [String]?
        let coverageHints: CoverageHints?
    }

    /// Identity / context for the final `CheckResult` — bundled so
    /// `packageResult` stays under the parameter-count lint.
    private struct ResultMetadata {
        let protocolLaw: String
        let tier: StrictnessTier
        let environment: Environment
    }

    private static func packageResult<Input: Sendable>(
        metadata: ResultMetadata,
        backendResult: BackendCheckResult<Input>,
        formatCounterexample: (Input, ErrorBox?) -> String,
        observed: ObservedSnapshots
    ) -> CheckResult {
        switch backendResult {
        case .passed(let trialsRun, let initialSeed):
            return CheckResult(
                protocolLaw: metadata.protocolLaw,
                tier: metadata.tier,
                trials: trialsRun,
                seed: initialSeed,
                environment: metadata.environment,
                outcome: .passed,
                nearMisses: observed.nearMisses,
                coverageHints: observed.coverageHints
            )
        case .failed(let trialsRun, let initialSeed, let failingInput, let thrownError):
            let counterexample = formatCounterexample(failingInput, thrownError)
            return CheckResult(
                protocolLaw: metadata.protocolLaw,
                tier: metadata.tier,
                trials: trialsRun,
                seed: initialSeed,
                environment: metadata.environment,
                outcome: .failed(counterexample: counterexample),
                nearMisses: observed.nearMisses,
                coverageHints: observed.coverageHints
            )
        }
    }
}
