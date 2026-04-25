public enum TrialBudget: Sendable, Hashable {
    case sanity
    case standard
    case exhaustive(Int = 10_000)
    case custom(trials: Int)

    public var trialCount: Int {
        switch self {
        case .sanity: return 100
        case .standard: return 1_000
        case .exhaustive(let n): return n
        case .custom(let n): return n
        }
    }
}
