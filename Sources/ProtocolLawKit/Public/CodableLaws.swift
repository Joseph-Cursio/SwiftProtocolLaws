import Foundation
import PropertyBased

/// Run `Codable` protocol laws over `T` (PRD §4.3, §4.7).
///
/// M2 implements **round-trip fidelity** (Conventional tier) under the three
/// PRD-specified modes (`.strict` / `.semantic(equivalent:)` /
/// `.partial(fields:)`). Encoder independence (Conventional) is deferred to a
/// follow-up — the multi-codec orchestration is straightforward but warrants
/// its own design pass for shared-seed semantics across encoders.
///
/// `T` must be `Equatable` for `.strict` mode; `.semantic` and `.partial` use
/// the caller's predicate / per-field comparison and don't read `==`. Most
/// Codable types in real Swift code are also Equatable, so requiring it keeps
/// the signature simple.
@discardableResult
public func checkCodableProtocolLaws<T: Codable & Equatable & Sendable, S: SendableSequenceType>(
    for type: T.Type = T.self,
    using generator: Generator<T, S>,
    mode: CodableRoundTripMode<T> = .strict,
    codec: CodableCodec<T> = .json,
    budget: TrialBudget = .standard,
    enforcement: EnforcementMode = .default,
    seed: Seed? = nil
) async throws -> [CheckResult] {
    let runner = TrialRunner()
    let env = Environment.current
    let trials = budget.trialCount
    let lawName = "Codable.roundTripFidelity[\(codec.identifier)]"

    let roundTrip = await runner.runPerTrial(
        protocolLaw: lawName,
        tier: .conventional,
        trials: trials,
        seed: seed,
        generator: generator,
        environment: env
    ) { gen, rng in
        let value = gen.run(using: &rng)
        let restored: T
        do {
            let data = try codec.encode(value)
            restored = try codec.decode(data)
        } catch {
            return .violation(counterexample: "x = \(value); encode/decode threw: \(error)")
        }
        return compare(value, restored, under: mode)
    }

    let results = [roundTrip]
    try ProtocolLawViolation.throwIfViolations(in: results, enforcement: enforcement)
    return results
}

private func compare<T>(
    _ original: T,
    _ restored: T,
    under mode: CodableRoundTripMode<T>
) -> TrialRunner.TrialOutcome where T: Equatable & Sendable {
    switch mode {
    case .strict:
        if original == restored { return .pass }
        return .violation(
            counterexample: "x = \(original), restored = \(restored); !(x == restored) under .strict"
        )
    case .semantic(let equivalent):
        if equivalent(original, restored) { return .pass }
        return .violation(
            counterexample: "x = \(original), restored = \(restored); semantic equivalence returned false"
        )
    case .partial(let fields):
        for keyPath in fields {
            let originalField = String(describing: original[keyPath: keyPath])
            let restoredField = String(describing: restored[keyPath: keyPath])
            if originalField != restoredField {
                return .violation(
                    counterexample: "x = \(original), restored = \(restored); "
                        + "field at \(keyPath) differs: \"\(originalField)\" vs \"\(restoredField)\""
                )
            }
        }
        return .pass
    }
}
