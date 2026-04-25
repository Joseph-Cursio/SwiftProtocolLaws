import PropertyBased

/// Run the four `Equatable` protocol laws over `T` (PRD §4.3).
///
/// All four laws are Strict tier — a violation is a bug. Equatable has no
/// inherited protocol law suite, so `LawSelection` is not exposed here.
@discardableResult
public func checkEquatableProtocolLaws<T: Equatable & Sendable, S: SendableSequenceType>(
    for type: T.Type = T.self,
    using generator: Generator<T, S>,
    budget: TrialBudget = .standard,
    enforcement: EnforcementMode = .default,
    seed: Seed? = nil
) async throws -> [CheckResult] {
    let runner = TrialRunner()
    let env = Environment.current
    let trials = budget.trialCount

    let reflexivity = await runner.runPerTrial(
        protocolLaw: "Equatable.reflexivity",
        tier: .strict,
        trials: trials,
        seed: seed,
        generator: generator,
        environment: env
    ) { gen, rng in
        let x = gen.run(using: &rng)
        if x == x { return .pass }
        return .violation(counterexample: "x = \(x); x == x evaluated to false")
    }

    let symmetry = await runner.runPerTrial(
        protocolLaw: "Equatable.symmetry",
        tier: .strict,
        trials: trials,
        seed: seed,
        generator: generator,
        environment: env
    ) { gen, rng in
        let x = gen.run(using: &rng)
        let y = gen.run(using: &rng)
        let xy = (x == y)
        let yx = (y == x)
        if xy == yx { return .pass }
        return .violation(counterexample: "x = \(x), y = \(y); x == y → \(xy), y == x → \(yx)")
    }

    let transitivity = await runner.runPerTrial(
        protocolLaw: "Equatable.transitivity",
        tier: .strict,
        trials: trials,
        seed: seed,
        generator: generator,
        environment: env
    ) { gen, rng in
        let x = gen.run(using: &rng)
        let y = gen.run(using: &rng)
        let z = gen.run(using: &rng)
        if x == y && y == z && !(x == z) {
            return .violation(counterexample: "x = \(x), y = \(y), z = \(z); x == y and y == z but x != z")
        }
        return .pass
    }

    // Defensive coverage. `!=` is dispatched through Equatable's protocol
    // witness as `!(lhs == rhs)`, so this law is structurally unviolable for
    // any T whose `==` is observed through generic dispatch (which is how
    // we observe it here). The check stays in case a future Swift change
    // makes `!=` independently overridable; today it always passes.
    let negationConsistency = await runner.runPerTrial(
        protocolLaw: "Equatable.negationConsistency",
        tier: .strict,
        trials: trials,
        seed: seed,
        generator: generator,
        environment: env
    ) { gen, rng in
        let x = gen.run(using: &rng)
        let y = gen.run(using: &rng)
        let neq = (x != y)
        let notEq = !(x == y)
        if neq == notEq { return .pass }
        return .violation(counterexample: "x = \(x), y = \(y); x != y → \(neq), !(x == y) → \(notEq)")
    }

    let results = [reflexivity, symmetry, transitivity, negationConsistency]
    try ProtocolLawViolation.throwIfViolations(in: results, enforcement: enforcement)
    return results
}
