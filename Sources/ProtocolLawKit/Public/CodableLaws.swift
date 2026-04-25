import Foundation
import PropertyBased

/// Run `Codable` protocol laws over `Value` (PRD §4.3, §4.7).
///
/// M2 implements **round-trip fidelity** (Conventional tier) under the three
/// PRD-specified modes (`.strict` / `.semantic(equivalent:)` /
/// `.partial(fields:)`). Encoder independence (Conventional) is deferred to a
/// follow-up — the multi-codec orchestration is straightforward but warrants
/// its own design pass for shared-seed semantics across encoders.
///
/// `Value` must be `Equatable` for `.strict` mode; `.semantic` and `.partial`
/// use the caller's predicate / per-field comparison and don't read `==`. Most
/// Codable types in real Swift code are also Equatable, so requiring it keeps
/// the signature simple.
@discardableResult
public func checkCodableProtocolLaws<
    Value: Codable & Equatable & Sendable,
    Shrinker: SendableSequenceType
>(
    for type: Value.Type = Value.self,
    using generator: Generator<Value, Shrinker>,
    config: CodableLawConfig<Value> = CodableLawConfig(),
    options: LawCheckOptions = LawCheckOptions()
) async throws -> [CheckResult] {
    let runner = TrialRunner(
        trials: options.budget.trialCount,
        seed: options.seed,
        generator: generator,
        environment: .current
    )
    let lawName = "Codable.roundTripFidelity[\(config.codec.identifier)]"
    let codec = config.codec
    let mode = config.mode
    let roundTrip = await runner.runPerTrial(
        protocolLaw: lawName,
        tier: .conventional
    ) { gen, rng in
        let value = gen.run(using: &rng)
        let restored: Value
        do {
            let data = try codec.encode(value)
            restored = try codec.decode(data)
        } catch {
            return .violation(counterexample: "x = \(value); encode/decode threw: \(error)")
        }
        return compare(value, restored, under: mode)
    }
    let results = [roundTrip]
    try ProtocolLawViolation.throwIfViolations(in: results, enforcement: options.enforcement)
    return results
}

private func compare<Value>(
    _ original: Value,
    _ restored: Value,
    under mode: CodableRoundTripMode<Value>
) -> TrialOutcome where Value: Equatable & Sendable {
    switch mode {
    case .strict:
        if original == restored { return .pass }
        return .violation(
            counterexample: "x = \(original), restored = \(restored); !(x == restored) under .strict"
        )
    case .semantic(let equivalent):
        if equivalent(original, restored) { return .pass }
        return .violation(
            counterexample: "x = \(original), restored = \(restored); "
                + "semantic equivalence returned false"
        )
    case .partial(let fields):
        return comparePartialFields(original, restored, fields: fields)
    }
}

private func comparePartialFields<Value>(
    _ original: Value,
    _ restored: Value,
    fields: [PartialKeyPath<Value>]
) -> TrialOutcome where Value: Equatable & Sendable {
    for keyPath in fields {
        let originalField = String(describing: original[keyPath: keyPath])
        let restoredField = String(describing: restored[keyPath: keyPath])
        if originalField != restoredField {
            return .violation(
                counterexample: "x = \(original), restored = \(restored); "
                    + "field at \(keyPath) differs: "
                    + "\"\(originalField)\" vs \"\(restoredField)\""
            )
        }
    }
    return .pass
}
