import PropertyBased

/// Run `Comparable` protocol laws over `T` (PRD §4.3).
///
/// Default `laws: .all` runs the inherited `Equatable` suite first per PRD §4.3
/// inheritance semantics; `.ownOnly` skips it.
///
/// Returned-array order: Equatable laws (when `.all`) then Comparable laws —
/// `antisymmetry` (Strict), `transitivity` (Strict), `totality` (Conventional),
/// `operatorConsistency` (Strict).
@discardableResult
public func checkComparableProtocolLaws<T: Comparable & Sendable, S: SendableSequenceType>(
    for type: T.Type = T.self,
    using generator: Generator<T, S>,
    budget: TrialBudget = .standard,
    enforcement: EnforcementMode = .default,
    seed: Seed? = nil,
    laws: LawSelection = .all
) async throws -> [CheckResult] {
    var results: [CheckResult] = []

    if laws == .all {
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

    let antisymmetry = await runner.runPerTrial(
        protocolLaw: "Comparable.antisymmetry",
        tier: .strict,
        trials: trials,
        seed: seed,
        generator: generator,
        environment: env
    ) { gen, rng in
        let x = gen.run(using: &rng)
        let y = gen.run(using: &rng)
        if x <= y && y <= x && !(x == y) {
            return .violation(counterexample: "x = \(x), y = \(y); x <= y and y <= x but x != y")
        }
        return .pass
    }

    let transitivity = await runner.runPerTrial(
        protocolLaw: "Comparable.transitivity",
        tier: .strict,
        trials: trials,
        seed: seed,
        generator: generator,
        environment: env
    ) { gen, rng in
        let x = gen.run(using: &rng)
        let y = gen.run(using: &rng)
        let z = gen.run(using: &rng)
        if x <= y && y <= z && !(x <= z) {
            return .violation(counterexample: "x = \(x), y = \(y), z = \(z); x <= y and y <= z but !(x <= z)")
        }
        return .pass
    }

    let totality = await runner.runPerTrial(
        protocolLaw: "Comparable.totality",
        tier: .conventional,
        trials: trials,
        seed: seed,
        generator: generator,
        environment: env
    ) { gen, rng in
        let x = gen.run(using: &rng)
        let y = gen.run(using: &rng)
        if !(x <= y) && !(y <= x) {
            return .violation(counterexample: "x = \(x), y = \(y); neither x <= y nor y <= x (NaN-like)")
        }
        return .pass
    }

    // `<=`, `>`, `>=` are derived from `<` by Comparable's protocol witnesses,
    // so this check can't catch "user overrode `<=` inconsistently with `<`"
    // through generic dispatch. It DOES catch "user's `<` is broken in a way
    // that makes the derived operators internally inconsistent" — e.g. `<`
    // returning true for both directions of a pair makes `x < y` and
    // `!(x <= y)` simultaneously true.
    let operatorConsistency = await runner.runPerTrial(
        protocolLaw: "Comparable.operatorConsistency",
        tier: .strict,
        trials: trials,
        seed: seed,
        generator: generator,
        environment: env
    ) { gen, rng in
        let x = gen.run(using: &rng)
        let y = gen.run(using: &rng)
        let lt = x < y
        let gt = x > y
        let le = x <= y
        let ge = x >= y
        if gt != (y < x) {
            return .violation(counterexample: "x = \(x), y = \(y); x > y → \(gt) but y < x → \(y < x)")
        }
        if ge != (y <= x) {
            return .violation(counterexample: "x = \(x), y = \(y); x >= y → \(ge) but y <= x → \(y <= x)")
        }
        if lt && le == false {
            return .violation(counterexample: "x = \(x), y = \(y); x < y but !(x <= y)")
        }
        return .pass
    }

    results.append(contentsOf: [antisymmetry, transitivity, totality, operatorConsistency])
    try ProtocolLawViolation.throwIfViolations(in: results, enforcement: enforcement)
    return results
}
