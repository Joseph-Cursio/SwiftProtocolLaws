import PropertyBased

/// Run `Comparable` protocol laws over `Value` (PRD §4.3).
///
/// Default `laws: .all` runs the inherited `Equatable` suite first per PRD
/// §4.3 inheritance semantics; `.ownOnly` skips it.
///
/// Returned-array order: Equatable laws (when `.all`) then Comparable laws —
/// `antisymmetry` (Strict), `transitivity` (Strict), `totality` (Conventional),
/// `operatorConsistency` (Strict).
@discardableResult
public func checkComparableProtocolLaws<Value: Comparable & Sendable, Shrinker: SendableSequenceType>(
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
        environment: .current
    )
    results.append(contentsOf: [
        await checkAntisymmetry(runner: runner),
        await checkTransitivity(runner: runner),
        await checkTotality(runner: runner),
        await checkOperatorConsistency(runner: runner)
    ])
    try ProtocolLawViolation.throwIfViolations(in: results, enforcement: options.enforcement)
    return results
}

private func collectInheritedEquatable<Value: Comparable & Sendable, Shrinker: SendableSequenceType>(
    for type: Value.Type,
    using generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> [CheckResult] {
    let inheritedOptions = LawCheckOptions(
        budget: options.budget,
        enforcement: .default,
        seed: options.seed
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

private func checkAntisymmetry<Value: Comparable & Sendable, Shrinker: SendableSequenceType>(
    runner: TrialRunner<Value, Shrinker>
) async -> CheckResult {
    await runner.runPerTrial(protocolLaw: "Comparable.antisymmetry", tier: .strict) { gen, rng in
        let first = gen.run(using: &rng)
        let second = gen.run(using: &rng)
        if first <= second && second <= first && !(first == second) {
            return .violation(
                counterexample: "x = \(first), y = \(second); x <= y and y <= x but x != y"
            )
        }
        return .pass
    }
}

private func checkTransitivity<Value: Comparable & Sendable, Shrinker: SendableSequenceType>(
    runner: TrialRunner<Value, Shrinker>
) async -> CheckResult {
    await runner.runPerTrial(protocolLaw: "Comparable.transitivity", tier: .strict) { gen, rng in
        let first = gen.run(using: &rng)
        let second = gen.run(using: &rng)
        let third = gen.run(using: &rng)
        if first <= second && second <= third && !(first <= third) {
            return .violation(
                counterexample: "x = \(first), y = \(second), z = \(third); "
                    + "x <= y and y <= z but !(x <= z)"
            )
        }
        return .pass
    }
}

private func checkTotality<Value: Comparable & Sendable, Shrinker: SendableSequenceType>(
    runner: TrialRunner<Value, Shrinker>
) async -> CheckResult {
    await runner.runPerTrial(protocolLaw: "Comparable.totality", tier: .conventional) { gen, rng in
        let first = gen.run(using: &rng)
        let second = gen.run(using: &rng)
        if !(first <= second) && !(second <= first) {
            return .violation(
                counterexample: "x = \(first), y = \(second); neither x <= y nor y <= x (NaN-like)"
            )
        }
        return .pass
    }
}

// `<=`, `>`, `>=` are derived from `<` by Comparable's protocol witnesses, so
// this check can't catch "user overrode `<=` inconsistently with `<`" through
// generic dispatch. It DOES catch "user's `<` is broken in a way that makes
// the derived operators internally inconsistent" — e.g. `<` returning true
// for both directions of a pair makes `x < y` and `!(x <= y)` simultaneously
// true.
private func checkOperatorConsistency<Value: Comparable & Sendable, Shrinker: SendableSequenceType>(
    runner: TrialRunner<Value, Shrinker>
) async -> CheckResult {
    await runner.runPerTrial(
        protocolLaw: "Comparable.operatorConsistency",
        tier: .strict
    ) { gen, rng in
        let first = gen.run(using: &rng)
        let second = gen.run(using: &rng)
        let lessThan = first < second
        let greaterThan = first > second
        let lessOrEqual = first <= second
        let greaterOrEqual = first >= second
        if greaterThan != (second < first) {
            return .violation(
                counterexample: "x = \(first), y = \(second); x > y → \(greaterThan) "
                    + "but y < x → \(second < first)"
            )
        }
        if greaterOrEqual != (second <= first) {
            return .violation(
                counterexample: "x = \(first), y = \(second); x >= y → \(greaterOrEqual) "
                    + "but y <= x → \(second <= first)"
            )
        }
        if lessThan && lessOrEqual == false {
            return .violation(
                counterexample: "x = \(first), y = \(second); x < y but !(x <= y)"
            )
        }
        return .pass
    }
}
