/// Single source of truth for protocol law check output formatting (PRD §4.6).
///
/// Per the PRD: every result includes its strictness tier, the trial budget, the
/// replayable seed, and the "empirical evidence, not a proof" disclaimer. M5's
/// confidence-reporting upgrade (near-misses, coverage hints, distribution stats)
/// will edit this one file rather than touching each law's call site.
internal enum ViolationFormatter {
    static func format(_ result: CheckResult) -> String {
        let glyph: String
        switch result.outcome {
        case .passed: glyph = "✓"
        case .failed: glyph = "✗"
        }
        var lines: [String] = []
        lines.append("\(glyph) \(result.protocolLaw)  [\(result.tier.rawValue.capitalized), \(result.trials) trials]")
        if case .failed(let counterexample) = result.outcome {
            lines.append("  Counterexample: \(counterexample)")
        }
        lines.append("  Replay with seed: \(result.seed.description)")
        lines.append("  (Empirical evidence, not a proof.)")
        return lines.joined(separator: "\n")
    }
}
