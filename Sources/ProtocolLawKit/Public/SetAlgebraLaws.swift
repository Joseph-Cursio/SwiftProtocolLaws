import PropertyBased

/// Run `SetAlgebra` protocol laws over `Value` (PRD §4.3).
///
/// Five Strict-tier laws — a violation under any of them is a bug:
/// - `unionIdempotence` — `x.union(x) == x`
/// - `intersectionIdempotence` — `x.intersection(x) == x`
/// - `unionCommutativity` — `x.union(y) == y.union(x)`
/// - `intersectionCommutativity` — `x.intersection(y) == y.intersection(x)`
/// - `emptyIdentity` — `x.union(Self()) == x` (the protocol's `init()`
///   produces the empty set)
///
/// `SetAlgebra` does not formally extend `Equatable`, but in practice every
/// stdlib SetAlgebra type is `Equatable` and the laws above compare
/// `Self == Self`. The signature requires `Equatable` rather than threading
/// a caller-supplied predicate.
@discardableResult
public func checkSetAlgebraProtocolLaws<
    Value: SetAlgebra & Equatable & Sendable,
    Shrinker: SendableSequenceType
>(
    for type: Value.Type = Value.self,
    using generator: Generator<Value, Shrinker>,
    options: LawCheckOptions = LawCheckOptions()
) async throws -> [CheckResult] {
    let runner = TrialRunner(
        trials: options.budget.trialCount,
        seed: options.seed,
        generator: generator,
        environment: .current,
        suppressions: options.suppressions
    )
    let results = [
        await checkUnionIdempotence(runner: runner),
        await checkIntersectionIdempotence(runner: runner),
        await checkUnionCommutativity(runner: runner),
        await checkIntersectionCommutativity(runner: runner),
        await checkEmptyIdentity(runner: runner)
    ]
    try ProtocolLawViolation.throwIfViolations(in: results, enforcement: options.enforcement)
    return results
}

private func checkUnionIdempotence<
    Value: SetAlgebra & Equatable & Sendable,
    Shrinker: SendableSequenceType
>(
    runner: TrialRunner<Value, Shrinker>
) async -> CheckResult {
    await runner.runPerTrial(
        protocolLaw: "SetAlgebra.unionIdempotence",
        tier: .strict
    ) { gen, rng in
        let sample = gen.run(using: &rng)
        let result = sample.union(sample)
        if result == sample { return .pass }
        return .violation(
            counterexample: "x = \(sample); x.union(x) = \(result), expected \(sample)"
        )
    }
}

private func checkIntersectionIdempotence<
    Value: SetAlgebra & Equatable & Sendable,
    Shrinker: SendableSequenceType
>(
    runner: TrialRunner<Value, Shrinker>
) async -> CheckResult {
    await runner.runPerTrial(
        protocolLaw: "SetAlgebra.intersectionIdempotence",
        tier: .strict
    ) { gen, rng in
        let sample = gen.run(using: &rng)
        let result = sample.intersection(sample)
        if result == sample { return .pass }
        return .violation(
            counterexample: "x = \(sample); x.intersection(x) = \(result), expected \(sample)"
        )
    }
}

private func checkUnionCommutativity<
    Value: SetAlgebra & Equatable & Sendable,
    Shrinker: SendableSequenceType
>(
    runner: TrialRunner<Value, Shrinker>
) async -> CheckResult {
    await runner.runPerTrial(
        protocolLaw: "SetAlgebra.unionCommutativity",
        tier: .strict
    ) { gen, rng in
        let first = gen.run(using: &rng)
        let second = gen.run(using: &rng)
        let forward = first.union(second)
        let reverse = second.union(first)
        if forward == reverse { return .pass }
        return .violation(
            counterexample: "x = \(first), y = \(second); "
                + "x.union(y) = \(forward), y.union(x) = \(reverse)"
        )
    }
}

private func checkIntersectionCommutativity<
    Value: SetAlgebra & Equatable & Sendable,
    Shrinker: SendableSequenceType
>(
    runner: TrialRunner<Value, Shrinker>
) async -> CheckResult {
    await runner.runPerTrial(
        protocolLaw: "SetAlgebra.intersectionCommutativity",
        tier: .strict
    ) { gen, rng in
        let first = gen.run(using: &rng)
        let second = gen.run(using: &rng)
        let forward = first.intersection(second)
        let reverse = second.intersection(first)
        if forward == reverse { return .pass }
        return .violation(
            counterexample: "x = \(first), y = \(second); "
                + "x.intersection(y) = \(forward), y.intersection(x) = \(reverse)"
        )
    }
}

private func checkEmptyIdentity<
    Value: SetAlgebra & Equatable & Sendable,
    Shrinker: SendableSequenceType
>(
    runner: TrialRunner<Value, Shrinker>
) async -> CheckResult {
    await runner.runPerTrial(
        protocolLaw: "SetAlgebra.emptyIdentity",
        tier: .strict
    ) { gen, rng in
        let sample = gen.run(using: &rng)
        let empty = Value()
        let result = sample.union(empty)
        if result == sample { return .pass }
        return .violation(
            counterexample: "x = \(sample); x.union(Self()) = \(result), expected \(sample)"
        )
    }
}
