/// Single boundary that every public `checkXxxProtocolLaws` function calls
/// before paying any trial budget — implements the PRD §4.6 environment
/// fingerprint replay validation.
///
/// No-op when `options.expectedReplayEnvironment == nil`. Otherwise compares
/// the expected fingerprint against `Environment.current(backend:)` under the
/// caller's `replayRelaxation` policy and throws `ReplayEnvironmentMismatch`
/// when they don't match.
internal enum ReplayEnvironmentValidator {
    static func verify(_ options: LawCheckOptions) throws {
        guard let expected = options.expectedReplayEnvironment else { return }
        let actual = Environment.current(backend: options.backend)
        if options.replayRelaxation.matches(expected: expected, actual: actual) { return }
        throw ReplayEnvironmentMismatch(expected: expected, actual: actual)
    }
}
