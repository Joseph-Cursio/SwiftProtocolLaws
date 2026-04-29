import PropertyBased

/// Run `RawRepresentable` protocol laws over `Value` (PRD §4.3).
///
/// `RawRepresentable` carries one Strict-tier law:
///
/// - **Round-trip fidelity**: `T(rawValue: x.rawValue) == x` for every value
///   the generator produces.
///
/// `Equatable` is required by the API (the law uses `==`) but
/// `RawRepresentable` does not refine `Equatable` in the stdlib hierarchy —
/// no inherited suite runs. Callers who want Equatable's own laws should
/// invoke `checkEquatableProtocolLaws` separately.
@discardableResult
public func checkRawRepresentableProtocolLaws<
    Value: RawRepresentable & Equatable & Sendable,
    Shrinker: SendableSequenceType
>(
    for type: Value.Type = Value.self,
    using generator: Generator<Value, Shrinker>,
    options: LawCheckOptions = LawCheckOptions()
) async throws -> [CheckResult] {
    try ReplayEnvironmentValidator.verify(options)
    let results = [
        await checkRoundTrip(generator: generator, options: options)
    ]
    try ProtocolLawViolation.throwIfViolations(in: results, enforcement: options.enforcement)
    return results
}

private func checkRoundTrip<
    Value: RawRepresentable & Equatable & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await PerLawDriver.run(
        protocolLaw: "RawRepresentable.roundTrip",
        tier: .strict,
        options: options,
        check: LawCheck(
            sample: { rng in generator.run(using: &rng) },
            property: { sample in
                guard let round = Value(rawValue: sample.rawValue) else { return false }
                return round == sample
            },
            formatCounterexample: { sample, _ in
                let raw = sample.rawValue
                if let round = Value(rawValue: raw) {
                    return "x = \(sample), x.rawValue = \(raw); "
                        + "T(rawValue: x.rawValue) = \(round), expected x"
                }
                return "x = \(sample), x.rawValue = \(raw); "
                    + "T(rawValue: x.rawValue) returned nil"
            }
        )
    )
}
