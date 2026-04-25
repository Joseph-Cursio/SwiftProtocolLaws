public struct ProtocolLawViolation: Error, Sendable, CustomStringConvertible {
    public let results: [CheckResult]

    public init(results: [CheckResult]) {
        self.results = results
    }

    public var description: String {
        results.map(ViolationFormatter.format).joined(separator: "\n\n")
    }

    static func throwIfViolations(in results: [CheckResult], enforcement: EnforcementMode) throws {
        let escalating = results.filter { result in
            // Only `.failed` outcomes can escalate. `.suppressed` and
            // `.expectedViolation` are explicit policy and never throw — see
            // PRD §4.7.
            result.isViolation && enforcement.shouldThrow(for: result.tier)
        }
        guard !escalating.isEmpty else { return }
        throw ProtocolLawViolation(results: escalating)
    }
}
