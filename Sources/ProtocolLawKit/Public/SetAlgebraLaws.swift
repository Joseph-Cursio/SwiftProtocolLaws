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
    let results = [
        await checkUnionIdempotence(generator: generator, options: options),
        await checkIntersectionIdempotence(generator: generator, options: options),
        await checkUnionCommutativity(generator: generator, options: options),
        await checkIntersectionCommutativity(generator: generator, options: options),
        await checkEmptyIdentity(generator: generator, options: options)
    ]
    try ProtocolLawViolation.throwIfViolations(in: results, enforcement: options.enforcement)
    return results
}

private func checkUnionIdempotence<
    Value: SetAlgebra & Equatable & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await PerLawDriver.run(
        protocolLaw: "SetAlgebra.unionIdempotence",
        tier: .strict,
        options: options,
        check: LawCheck(
            sample: { rng in generator.run(using: &rng) },
            property: { sample in sample.union(sample) == sample },
            formatCounterexample: { sample, _ in
                "x = \(sample); x.union(x) = \(sample.union(sample)), expected \(sample)"
            }
        )
    )
}

private func checkIntersectionIdempotence<
    Value: SetAlgebra & Equatable & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await PerLawDriver.run(
        protocolLaw: "SetAlgebra.intersectionIdempotence",
        tier: .strict,
        options: options,
        check: LawCheck(
            sample: { rng in generator.run(using: &rng) },
            property: { sample in sample.intersection(sample) == sample },
            formatCounterexample: { sample, _ in
                "x = \(sample); x.intersection(x) = \(sample.intersection(sample)), "
                    + "expected \(sample)"
            }
        )
    )
}

private func checkUnionCommutativity<
    Value: SetAlgebra & Equatable & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await PerLawDriver.run(
        protocolLaw: "SetAlgebra.unionCommutativity",
        tier: .strict,
        options: options,
        check: LawCheck(
            sample: { rng in (generator.run(using: &rng), generator.run(using: &rng)) },
            property: { input in
                let (first, second) = input
                return first.union(second) == second.union(first)
            },
            formatCounterexample: { input, _ in
                let (first, second) = input
                return "x = \(first), y = \(second); x.union(y) = \(first.union(second)), "
                    + "y.union(x) = \(second.union(first))"
            }
        )
    )
}

private func checkIntersectionCommutativity<
    Value: SetAlgebra & Equatable & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await PerLawDriver.run(
        protocolLaw: "SetAlgebra.intersectionCommutativity",
        tier: .strict,
        options: options,
        check: LawCheck(
            sample: { rng in (generator.run(using: &rng), generator.run(using: &rng)) },
            property: { input in
                let (first, second) = input
                return first.intersection(second) == second.intersection(first)
            },
            formatCounterexample: { input, _ in
                let (first, second) = input
                return "x = \(first), y = \(second); "
                    + "x.intersection(y) = \(first.intersection(second)), "
                    + "y.intersection(x) = \(second.intersection(first))"
            }
        )
    )
}

private func checkEmptyIdentity<
    Value: SetAlgebra & Equatable & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await PerLawDriver.run(
        protocolLaw: "SetAlgebra.emptyIdentity",
        tier: .strict,
        options: options,
        check: LawCheck(
            sample: { rng in generator.run(using: &rng) },
            property: { sample in sample.union(Value()) == sample },
            formatCounterexample: { sample, _ in
                "x = \(sample); x.union(Self()) = \(sample.union(Value())), expected \(sample)"
            }
        )
    )
}
