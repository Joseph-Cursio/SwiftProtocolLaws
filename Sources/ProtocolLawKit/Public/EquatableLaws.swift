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
    try ReplayEnvironmentValidator.verify(options)
    let results = [
        await checkReflexivity(generator: generator, options: options),
        await checkSymmetry(generator: generator, options: options),
        await checkTransitivity(generator: generator, options: options),
        await checkNegationConsistency(generator: generator, options: options)
    ]
    try ProtocolLawViolation.throwIfViolations(in: results, enforcement: options.enforcement)
    return results
}

private func checkReflexivity<Value: Equatable & Sendable, Shrinker: SendableSequenceType>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await PerLawDriver.run(
        protocolLaw: "Equatable.reflexivity",
        tier: .strict,
        options: options,
        check: LawCheck(
            sample: { rng in generator.run(using: &rng) },
            property: { sample in sample == sample },
            formatCounterexample: { sample, _ in
                "x = \(sample); x == x evaluated to false"
            }
        )
    )
}

private func checkSymmetry<Value: Equatable & Sendable, Shrinker: SendableSequenceType>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await PerLawDriver.run(
        protocolLaw: "Equatable.symmetry",
        tier: .strict,
        options: options,
        check: LawCheck(
            sample: { rng in (generator.run(using: &rng), generator.run(using: &rng)) },
            property: { input in
                let (first, second) = input
                return (first == second) == (second == first)
            },
            formatCounterexample: { input, _ in
                let (first, second) = input
                return "x = \(first), y = \(second); "
                    + "x == y → \(first == second), y == x → \(second == first)"
            }
        )
    )
}

private func checkTransitivity<Value: Equatable & Sendable, Shrinker: SendableSequenceType>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await PerLawDriver.run(
        protocolLaw: "Equatable.transitivity",
        tier: .strict,
        options: options,
        check: LawCheck(
            sample: { rng in
                (generator.run(using: &rng), generator.run(using: &rng), generator.run(using: &rng))
            },
            property: { input in
                let (first, second, third) = input
                return !(first == second && second == third) || (first == third)
            },
            formatCounterexample: { input, _ in
                let (first, second, third) = input
                return "x = \(first), y = \(second), z = \(third); "
                    + "x == y and y == z but x != z"
            }
        )
    )
}

// Defensive coverage. `!=` is dispatched through Equatable's protocol witness
// as `!(lhs == rhs)`, so this law is structurally unviolable for any Value
// whose `==` is observed through generic dispatch. The check stays in case a
// future Swift change makes `!=` independently overridable; today it always
// passes.
private func checkNegationConsistency<Value: Equatable & Sendable, Shrinker: SendableSequenceType>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await PerLawDriver.run(
        protocolLaw: "Equatable.negationConsistency",
        tier: .strict,
        options: options,
        check: LawCheck(
            sample: { rng in (generator.run(using: &rng), generator.run(using: &rng)) },
            property: { input in
                let (first, second) = input
                return (first != second) == !(first == second)
            },
            formatCounterexample: { input, _ in
                let (first, second) = input
                return "x = \(first), y = \(second); "
                    + "x != y → \(first != second), !(x == y) → \(!(first == second))"
            }
        )
    )
}
