import PropertyBased

/// Run `Hashable` protocol laws over `T` (PRD §4.3).
///
/// By default (`laws: .all`), the inherited `Equatable` suite runs first per
/// PRD §4.3 inheritance semantics. Pass `laws: .ownOnly` to skip Equatable.
///
/// Returned array order: Equatable laws (if `.all`) then Hashable laws —
/// `equalityConsistency` (Strict), `stabilityWithinProcess` (Conventional),
/// `distribution` (Heuristic).
@discardableResult
public func checkHashableProtocolLaws<T: Hashable & Sendable, S: SendableSequenceType>(
    for type: T.Type = T.self,
    using generator: Generator<T, S>,
    budget: TrialBudget = .standard,
    enforcement: EnforcementMode = .default,
    seed: Seed? = nil,
    laws: LawSelection = .all
) async throws -> [CheckResult] {
    var results: [CheckResult] = []

    if laws == .all {
        // Run inherited Equatable suite without throwing — collect all results
        // first, then escalate at the end so the caller sees the full picture.
        do {
            let equatableResults = try await checkEquatableProtocolLaws(
                for: type,
                using: generator,
                budget: budget,
                enforcement: .default,
                seed: seed
            )
            results.append(contentsOf: equatableResults)
        } catch let violation as ProtocolLawViolation {
            results.append(contentsOf: violation.results)
        }
    }

    let runner = TrialRunner()
    let env = Environment.current
    let trials = budget.trialCount

    let equalityConsistency = await runner.runPerTrial(
        protocolLaw: "Hashable.equalityConsistency",
        tier: .strict,
        trials: trials,
        seed: seed,
        generator: generator,
        environment: env
    ) { gen, rng in
        let x = gen.run(using: &rng)
        let y = gen.run(using: &rng)
        if x == y && x.hashValue != y.hashValue {
            return .violation(counterexample: "x = \(x), y = \(y); x == y but hashValues differ (\(x.hashValue) vs \(y.hashValue))")
        }
        return .pass
    }

    let stability = await runner.runPerTrial(
        protocolLaw: "Hashable.stabilityWithinProcess",
        tier: .conventional,
        trials: trials,
        seed: seed,
        generator: generator,
        environment: env
    ) { gen, rng in
        let x = gen.run(using: &rng)
        let h1 = x.hashValue
        let h2 = x.hashValue
        if h1 == h2 { return .pass }
        return .violation(counterexample: "x = \(x); hashValue returned \(h1) then \(h2) within the same process")
    }

    let distribution = await runner.runAggregate(
        protocolLaw: "Hashable.distribution",
        tier: .heuristic,
        trials: trials,
        seed: seed,
        generator: generator,
        environment: env
    ) { gen, rng, count in
        var hashes = Set<Int>()
        var lastSample: T?
        for _ in 0..<count {
            let x = gen.run(using: &rng)
            lastSample = x
            hashes.insert(x.hashValue)
        }
        let denominator = max(count, 1)
        let uniqueRatio = Double(hashes.count) / Double(denominator)
        // Threshold of 0.10: a generator producing fewer than 10% unique
        // hashes across the trial budget signals a degenerate distribution.
        // The ratio matches the PRD §4.6 "hash distribution sanity" intent
        // without claiming statistical rigor — this is Heuristic tier.
        if uniqueRatio < 0.10 {
            let sampleStr = lastSample.map { "\($0)" } ?? "<no samples>"
            let ratioStr = String(format: "%.3f", uniqueRatio)
            let counter = "\(count) samples produced only \(hashes.count) unique hashValues "
                + "(ratio \(ratioStr)); last sample: \(sampleStr)"
            return .violation(counterexample: counter)
        }
        return .pass
    }

    results.append(contentsOf: [equalityConsistency, stability, distribution])
    try ProtocolLawViolation.throwIfViolations(in: results, enforcement: enforcement)
    return results
}
