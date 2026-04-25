public enum EnforcementMode: Sendable, Hashable {
    /// Strict-tier violations fail; Conventional and Heuristic violations are reported but do not throw.
    case `default`

    /// All violations regardless of tier cause `checkXxxProtocolLaws` to throw.
    case strict
}

extension EnforcementMode {
    func shouldThrow(for tier: StrictnessTier) -> Bool {
        switch self {
        case .default:
            return tier == .strict
        case .strict:
            return true
        }
    }
}
