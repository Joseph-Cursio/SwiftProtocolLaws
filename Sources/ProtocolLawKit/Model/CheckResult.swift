public struct CheckResult: Sendable, Hashable {
    public enum Outcome: Sendable, Hashable {
        case passed
        case failed(counterexample: String)
    }

    public let protocolLaw: String
    public let tier: StrictnessTier
    public let trials: Int
    public let seed: Seed
    public let environment: Environment
    public let outcome: Outcome

    /// Inputs that came close to violating the law.
    /// Per PRD §4.6: `nil` means the backend doesn't track near-misses (distinct from `[]`).
    /// M1's loop doesn't track near-misses; field is always `nil` until M5.
    public let nearMisses: [String]?

    /// Distribution / boundary metadata. Reserved; see PRD §4.6. M1 always reports `nil`.
    public let coverageHints: CoverageHints?

    public init(
        protocolLaw: String,
        tier: StrictnessTier,
        trials: Int,
        seed: Seed,
        environment: Environment,
        outcome: Outcome,
        nearMisses: [String]? = nil,
        coverageHints: CoverageHints? = nil
    ) {
        self.protocolLaw = protocolLaw
        self.tier = tier
        self.trials = trials
        self.seed = seed
        self.environment = environment
        self.outcome = outcome
        self.nearMisses = nearMisses
        self.coverageHints = coverageHints
    }

    public var isViolation: Bool {
        if case .failed = outcome { return true }
        return false
    }

    public var counterexample: String? {
        if case .failed(let counterexample) = outcome { return counterexample }
        return nil
    }
}

public struct CoverageHints: Sendable, Hashable {
    public let inputClasses: [String: Int]
    public let boundaryHits: [String: Int]

    public init(inputClasses: [String: Int], boundaryHits: [String: Int]) {
        self.inputClasses = inputClasses
        self.boundaryHits = boundaryHits
    }
}
