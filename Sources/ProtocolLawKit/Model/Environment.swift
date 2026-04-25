// Environment fingerprint per PRD §4.6.
//
// M1 records `swiftVersion` and `backendIdentity`. `generatorSchemaHash` is the
// hash of the registered generator schema; the generator registry doesn't exist
// until M3, so M1 ships a placeholder. Replay-mismatch validation logic is M5
// scope — recording the fingerprint now lets seeds carried in CI artifacts
// remain meaningful once the validator lands, without a breaking API change.

public struct Environment: Sendable, Hashable, Codable {
    public let swiftVersion: String
    public let backendIdentity: String
    public let generatorSchemaHash: String

    public init(swiftVersion: String, backendIdentity: String, generatorSchemaHash: String) {
        self.swiftVersion = swiftVersion
        self.backendIdentity = backendIdentity
        self.generatorSchemaHash = generatorSchemaHash
    }

    public static var current: Environment {
        Environment(
            swiftVersion: detectedSwiftVersion,
            backendIdentity: "swift-property-based",
            generatorSchemaHash: "m1-no-registry"
        )
    }
}

private let detectedSwiftVersion: String = {
    #if swift(>=6.3)
    return "6.3+"
    #elseif swift(>=6.2)
    return "6.2"
    #elseif swift(>=6.1)
    return "6.1"
    #else
    return "<6.1"
    #endif
}()
