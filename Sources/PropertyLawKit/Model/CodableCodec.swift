import Foundation

/// A `(encode, decode)` pair plumbed into `checkCodablePropertyLaws`.
///
/// The codec is closure-based rather than wrapping `JSONEncoder` / `JSONDecoder`
/// directly because Foundation's encoders are not `Sendable` (they expose
/// mutable configuration). Wrapping encode/decode in `@Sendable` closures —
/// each constructing a fresh encoder per call — is the cheapest way to keep
/// the law-runner closures Sendable under Swift 6 strict concurrency.
public struct CodableCodec<T: Codable & Sendable>: Sendable {
    public let identifier: String
    public let encode: @Sendable (T) throws -> Data
    public let decode: @Sendable (Data) throws -> T

    public init(
        identifier: String,
        encode: @escaping @Sendable (T) throws -> Data,
        decode: @escaping @Sendable (Data) throws -> T
    ) {
        self.identifier = identifier
        self.encode = encode
        self.decode = decode
    }

    /// Default codec: `JSONEncoder` / `JSONDecoder` with stock options.
    public static var json: Self {
        Self(
            identifier: "JSON",
            encode: { value in try JSONEncoder().encode(value) },
            decode: { data in try JSONDecoder().decode(T.self, from: data) }
        )
    }

    /// `PropertyListEncoder` / `PropertyListDecoder` with binary format.
    public static var binaryPlist: Self {
        Self(
            identifier: "PropertyList(binary)",
            encode: { value in
                let encoder = PropertyListEncoder()
                encoder.outputFormat = .binary
                return try encoder.encode(value)
            },
            decode: { data in try PropertyListDecoder().decode(T.self, from: data) }
        )
    }
}
