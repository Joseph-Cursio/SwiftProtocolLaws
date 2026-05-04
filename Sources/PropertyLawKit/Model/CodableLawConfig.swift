/// Codable-specific configuration: the round-trip mode and the codec used
/// to perform the round-trip. Bundled because the two parameters always vary
/// together at call sites — choosing `.partial(fields:)` usually pairs with
/// a specific codec, and mixing modes across codecs is rare in practice.
public struct CodableLawConfig<Value: Codable & Sendable>: Sendable {
    public let mode: CodableRoundTripMode<Value>
    public let codec: CodableCodec<Value>

    public init(
        mode: CodableRoundTripMode<Value> = .strict,
        codec: CodableCodec<Value> = .json
    ) {
        self.mode = mode
        self.codec = codec
    }
}
