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
    try ReplayEnvironmentValidator.verify(options)
    var results: [CheckResult] = []
    if laws == .all {
        results.append(contentsOf: await collectInheritedEquatable(
            for: type,
            using: generator,
            options: options
        ))
    }
    results.append(contentsOf: [
        await checkEqualityConsistency(generator: generator, options: options),
        await checkStabilityWithinProcess(generator: generator, options: options),
        await checkDistribution(generator: generator, options: options)
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
        suppressions: options.suppressions,
        backend: options.backend
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
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await PerLawDriver.run(
        protocolLaw: "Hashable.equalityConsistency",
        tier: .strict,
        options: options,
        check: LawCheck(
            sample: { rng in (generator.run(using: &rng), generator.run(using: &rng)) },
            property: { input in
                let (first, second) = input
                return !(first == second) || (first.hashValue == second.hashValue)
            },
            formatCounterexample: { input, _ in
                let (first, second) = input
                return "x = \(first), y = \(second); x == y but hashValues differ "
                    + "(\(first.hashValue) vs \(second.hashValue))"
            }
        )
    )
}

private func checkStabilityWithinProcess<Value: Hashable & Sendable, Shrinker: SendableSequenceType>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await PerLawDriver.run(
        protocolLaw: "Hashable.stabilityWithinProcess",
        tier: .conventional,
        options: options,
        check: LawCheck(
            sample: { rng in generator.run(using: &rng) },
            property: { sample in sample.hashValue == sample.hashValue },
            formatCounterexample: { sample, _ in
                "x = \(sample); hashValue returned \(sample.hashValue) "
                    + "then \(sample.hashValue) within the same process"
            }
        )
    )
}

// Threshold of 0.10: a generator producing fewer than 10% unique hashes across
// the trial budget signals a degenerate distribution. The ratio matches the
// PRD §4.6 "hash distribution sanity" intent without claiming statistical
// rigor — this is Heuristic tier. Aggregate-mode (kit-side loop): the
// PropertyBackend protocol intentionally doesn't model whole-budget laws.
private func checkDistribution<Value: Hashable & Sendable, Shrinker: SendableSequenceType>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await AggregateDriver.run(
        protocolLaw: "Hashable.distribution",
        tier: .heuristic,
        options: options
    ) { rng, count in
        var hashes = Set<Int>()
        var lastSample: Value?
        for _ in 0..<count {
            let sample = generator.run(using: &rng)
            lastSample = sample
            hashes.insert(sample.hashValue)
        }
        let denominator = max(count, 1)
        let uniqueRatio = Double(hashes.count) / Double(denominator)
        if uniqueRatio < 0.10 {
            let sampleStr = lastSample.map { "\($0)" } ?? "<no samples>"
            let ratioStr = String(format: "%.3f", uniqueRatio)
            return .failed(counterexample:
                "\(count) samples produced only \(hashes.count) unique "
                    + "hashValues (ratio \(ratioStr)); last sample: \(sampleStr)"
            )
        }
        return .passed
    }
}
