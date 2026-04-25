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
    let lawName = "Codable.roundTripFidelity[\(config.codec.identifier)]"
    let codec = config.codec
    let mode = config.mode
    let result = await PerLawDriver.run(
        protocolLaw: lawName,
        tier: .conventional,
        options: options,
        check: LawCheck(
            sample: { rng in
                CodableTrial<Value>.run(generator: generator, rng: &rng, codec: codec)
            },
            property: { trial in
                switch trial {
                case .roundTripped(let original, let restored):
                    return comparesEqual(original, restored, mode: mode)
                case .threw:
                    return false
                }
            },
            formatCounterexample: { trial, _ in
                CodableTrial<Value>.format(trial: trial, mode: mode)
            }
        )
    )
    let results = [result]
    try ProtocolLawViolation.throwIfViolations(in: results, enforcement: options.enforcement)
    return results
}

/// Whole-trial sample for Codable: captures the original input, the restored
/// value (or the encode/decode error), in a Sendable shape so the backend
/// closure boundary stays clean.
private enum CodableTrial<Value: Codable & Equatable & Sendable>: Sendable {
    case roundTripped(original: Value, restored: Value)
    case threw(original: Value, error: ErrorBox)

    static func run<Shrinker: SendableSequenceType>(
        generator: Generator<Value, Shrinker>,
        rng: inout Xoshiro,
        codec: CodableCodec<Value>
    ) -> CodableTrial<Value> {
        let value = generator.run(using: &rng)
        do {
            let data = try codec.encode(value)
            let restored = try codec.decode(data)
            return .roundTripped(original: value, restored: restored)
        } catch {
            return .threw(original: value, error: ErrorBox(error))
        }
    }

    static func format(trial: CodableTrial<Value>, mode: CodableRoundTripMode<Value>) -> String {
        switch trial {
        case .roundTripped(let original, let restored):
            return formatMismatch(original: original, restored: restored, mode: mode)
        case .threw(let original, let error):
            return "x = \(original); encode/decode threw: \(error.message)"
        }
    }
}

private func comparesEqual<Value>(
    _ original: Value,
    _ restored: Value,
    mode: CodableRoundTripMode<Value>
) -> Bool where Value: Equatable & Sendable {
    switch mode {
    case .strict:
        return original == restored
    case .semantic(let equivalent):
        return equivalent(original, restored)
    case .partial(let fields):
        for keyPath in fields {
            let originalField = String(describing: original[keyPath: keyPath])
            let restoredField = String(describing: restored[keyPath: keyPath])
            if originalField != restoredField { return false }
        }
        return true
    }
}

private func formatMismatch<Value>(
    original: Value,
    restored: Value,
    mode: CodableRoundTripMode<Value>
) -> String where Value: Equatable & Sendable {
    switch mode {
    case .strict:
        return "x = \(original), restored = \(restored); !(x == restored) under .strict"
    case .semantic:
        return "x = \(original), restored = \(restored); semantic equivalence returned false"
    case .partial(let fields):
        for keyPath in fields {
            let originalField = String(describing: original[keyPath: keyPath])
            let restoredField = String(describing: restored[keyPath: keyPath])
            if originalField != restoredField {
                return "x = \(original), restored = \(restored); "
                    + "field at \(keyPath) differs: "
                    + "\"\(originalField)\" vs \"\(restoredField)\""
            }
        }
        return "x = \(original), restored = \(restored); .partial mode failure"
    }
}
