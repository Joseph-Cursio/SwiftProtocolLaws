import PropertyBased

/// Run the four `Equatable` protocol laws over `Value` (PRD §4.3).
///
/// All four laws are Strict tier — a violation is a bug. Equatable has no
/// inherited protocol law suite, so `LawSelection` is not exposed here.
@discardableResult
public func checkEquatableProtocolLaws<Value: Equatable & Sendable, Shrinker: SendableSequenceType>(
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
        await checkReflexivity(runner: runner),
        await checkSymmetry(runner: runner),
        await checkTransitivity(runner: runner),
        await checkNegationConsistency(runner: runner)
    ]
    try ProtocolLawViolation.throwIfViolations(in: results, enforcement: options.enforcement)
    return results
}

private func checkReflexivity<Value: Equatable & Sendable, Shrinker: SendableSequenceType>(
    runner: TrialRunner<Value, Shrinker>
) async -> CheckResult {
    await runner.runPerTrial(protocolLaw: "Equatable.reflexivity", tier: .strict) { gen, rng in
        let sample = gen.run(using: &rng)
        if sample == sample { return .pass }
        return .violation(counterexample: "x = \(sample); x == x evaluated to false")
    }
}

private func checkSymmetry<Value: Equatable & Sendable, Shrinker: SendableSequenceType>(
    runner: TrialRunner<Value, Shrinker>
) async -> CheckResult {
    await runner.runPerTrial(protocolLaw: "Equatable.symmetry", tier: .strict) { gen, rng in
        let first = gen.run(using: &rng)
        let second = gen.run(using: &rng)
        let forward = (first == second)
        let reverse = (second == first)
        if forward == reverse { return .pass }
        return .violation(
            counterexample: "x = \(first), y = \(second); x == y → \(forward), y == x → \(reverse)"
        )
    }
}

private func checkTransitivity<Value: Equatable & Sendable, Shrinker: SendableSequenceType>(
    runner: TrialRunner<Value, Shrinker>
) async -> CheckResult {
    await runner.runPerTrial(protocolLaw: "Equatable.transitivity", tier: .strict) { gen, rng in
        let first = gen.run(using: &rng)
        let second = gen.run(using: &rng)
        let third = gen.run(using: &rng)
        if first == second && second == third && !(first == third) {
            return .violation(
                counterexample: "x = \(first), y = \(second), z = \(third); "
                    + "x == y and y == z but x != z"
            )
        }
        return .pass
    }
}

// Defensive coverage. `!=` is dispatched through Equatable's protocol witness
// as `!(lhs == rhs)`, so this law is structurally unviolable for any Value
// whose `==` is observed through generic dispatch. The check stays in case a
// future Swift change makes `!=` independently overridable; today it always
// passes.
private func checkNegationConsistency<Value: Equatable & Sendable, Shrinker: SendableSequenceType>(
    runner: TrialRunner<Value, Shrinker>
) async -> CheckResult {
    await runner.runPerTrial(protocolLaw: "Equatable.negationConsistency", tier: .strict) { gen, rng in
        let first = gen.run(using: &rng)
        let second = gen.run(using: &rng)
        let nonEqual = (first != second)
        let notEqual = !(first == second)
        if nonEqual == notEqual { return .pass }
        return .violation(
            counterexample: "x = \(first), y = \(second); x != y → \(nonEqual), !(x == y) → \(notEqual)"
        )
    }
}
