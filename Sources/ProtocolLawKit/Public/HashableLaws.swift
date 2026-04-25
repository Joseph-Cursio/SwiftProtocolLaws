import PropertyBased

/// Run `Hashable` protocol laws over `Value` (PRD §4.3).
///
/// By default (`laws: .all`), the inherited `Equatable` suite runs first per
/// PRD §4.3 inheritance semantics. Pass `laws: .ownOnly` to skip Equatable.
///
/// Returned array order: Equatable laws (if `.all`) then Hashable laws —
/// `equalityConsistency` (Strict), `stabilityWithinProcess` (Conventional),
/// `distribution` (Heuristic).
@discardableResult
public func checkHashableProtocolLaws<Value: Hashable & Sendable, Shrinker: SendableSequenceType>(
    for type: Value.Type = Value.self,
    using generator: Generator<Value, Shrinker>,
    options: LawCheckOptions = LawCheckOptions(),
    laws: LawSelection = .all
) async throws -> [CheckResult] {
    var results: [CheckResult] = []
    if laws == .all {
        results.append(contentsOf: await collectInheritedEquatable(
            for: type,
            using: generator,
            options: options
        ))
    }
    let runner = TrialRunner(
        trials: options.budget.trialCount,
        seed: options.seed,
        generator: generator,
        environment: .current,
        suppressions: options.suppressions
    )
    results.append(contentsOf: [
        await checkEqualityConsistency(runner: runner),
        await checkStabilityWithinProcess(runner: runner),
        await checkDistribution(runner: runner)
    ])
    try ProtocolLawViolation.throwIfViolations(in: results, enforcement: options.enforcement)
    return results
}

private func collectInheritedEquatable<Value: Hashable & Sendable, Shrinker: SendableSequenceType>(
    for type: Value.Type,
    using generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> [CheckResult] {
    let inheritedOptions = LawCheckOptions(
        budget: options.budget,
        enforcement: .default,
        seed: options.seed,
        suppressions: options.suppressions
    )
    do {
        return try await checkEquatableProtocolLaws(
            for: type,
            using: generator,
            options: inheritedOptions
        )
    } catch let violation as ProtocolLawViolation {
        return violation.results
    } catch {
        return []
    }
}

private func checkEqualityConsistency<Value: Hashable & Sendable, Shrinker: SendableSequenceType>(
    runner: TrialRunner<Value, Shrinker>
) async -> CheckResult {
    await runner.runPerTrial(
        protocolLaw: "Hashable.equalityConsistency",
        tier: .strict
    ) { gen, rng in
        let first = gen.run(using: &rng)
        let second = gen.run(using: &rng)
        if first == second && first.hashValue != second.hashValue {
            return .violation(
                counterexample: "x = \(first), y = \(second); x == y but hashValues differ "
                    + "(\(first.hashValue) vs \(second.hashValue))"
            )
        }
        return .pass
    }
}

private func checkStabilityWithinProcess<Value: Hashable & Sendable, Shrinker: SendableSequenceType>(
    runner: TrialRunner<Value, Shrinker>
) async -> CheckResult {
    await runner.runPerTrial(
        protocolLaw: "Hashable.stabilityWithinProcess",
        tier: .conventional
    ) { gen, rng in
        let sample = gen.run(using: &rng)
        let firstHash = sample.hashValue
        let secondHash = sample.hashValue
        if firstHash == secondHash { return .pass }
        return .violation(
            counterexample: "x = \(sample); hashValue returned \(firstHash) "
                + "then \(secondHash) within the same process"
        )
    }
}

// Threshold of 0.10: a generator producing fewer than 10% unique hashes across
// the trial budget signals a degenerate distribution. The ratio matches the
// PRD §4.6 "hash distribution sanity" intent without claiming statistical
// rigor — this is Heuristic tier.
private func checkDistribution<Value: Hashable & Sendable, Shrinker: SendableSequenceType>(
    runner: TrialRunner<Value, Shrinker>
) async -> CheckResult {
    await runner.runAggregate(
        protocolLaw: "Hashable.distribution",
        tier: .heuristic
    ) { gen, rng, count in
        var hashes = Set<Int>()
        var lastSample: Value?
        for _ in 0..<count {
            let sample = gen.run(using: &rng)
            lastSample = sample
            hashes.insert(sample.hashValue)
        }
        let denominator = max(count, 1)
        let uniqueRatio = Double(hashes.count) / Double(denominator)
        if uniqueRatio < 0.10 {
            let sampleStr = lastSample.map { "\($0)" } ?? "<no samples>"
            let ratioStr = String(format: "%.3f", uniqueRatio)
            return .violation(
                counterexample: "\(count) samples produced only \(hashes.count) unique "
                    + "hashValues (ratio \(ratioStr)); last sample: \(sampleStr)"
            )
        }
        return .pass
    }
}
