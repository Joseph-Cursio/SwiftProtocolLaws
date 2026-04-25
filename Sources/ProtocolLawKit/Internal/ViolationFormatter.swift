/// Single source of truth for protocol law check output formatting (PRD §4.6, §4.7).
///
/// Every result includes its strictness tier, the trial budget, the replayable
/// seed, and the "empirical evidence, not a proof" disclaimer. M5's confidence-
/// reporting upgrade adds optional near-miss and coverage blocks that surface
/// only when the per-law check populated them — preserving the §4.6 contract
/// where `nil` means "this law/backend doesn't track" and `[]` /  empty
/// counts mean "tracked but found none".
internal enum ViolationFormatter {
    static func format(_ result: CheckResult) -> String {
        var lines: [String] = []
        lines.append(headerLine(result))
        if let outcomeBody = outcomeBodyLines(result.outcome) {
            lines.append(contentsOf: outcomeBody)
        }
        if let nearMissBody = nearMissLines(result.nearMisses) {
            lines.append(contentsOf: nearMissBody)
        }
        if let coverageBody = coverageLines(result.coverageHints) {
            lines.append(contentsOf: coverageBody)
        }
        lines.append("  Replay with seed: \(result.seed.description)")
        lines.append("  (Empirical evidence, not a proof.)")
        return lines.joined(separator: "\n")
    }

    private static func headerLine(_ result: CheckResult) -> String {
        let glyph: String
        switch result.outcome {
        case .passed: glyph = "✓"
        case .failed: glyph = "✗"
        case .suppressed: glyph = "…"
        case .expectedViolation: glyph = "⊘"
        }
        return "\(glyph) \(result.protocolLaw)  "
            + "[\(result.tier.rawValue.capitalized), \(result.trials) trials]"
    }

    private static func outcomeBodyLines(_ outcome: CheckResult.Outcome) -> [String]? {
        switch outcome {
        case .passed:
            return nil
        case .failed(let counterexample):
            return ["  Counterexample: \(counterexample)"]
        case .suppressed(let reason):
            return ["  Suppressed: \(reason)"]
        case .expectedViolation(let reason, let counterexample):
            return [
                "  Expected violation: \(reason)",
                "  Counterexample: \(counterexample)"
            ]
        }
    }

    /// Render up to a small cap of near-miss entries. Skipped entirely when
    /// `nearMisses == nil` (the law doesn't track them) and rendered as a
    /// "no near-misses" line when the kit tracked but found none.
    private static func nearMissLines(_ nearMisses: [String]?) -> [String]? {
        guard let nearMisses else { return nil }
        if nearMisses.isEmpty {
            return ["  Near-misses: none."]
        }
        let cap = 5
        var lines: [String] = ["  Near-misses (\(nearMisses.count)):"]
        for entry in nearMisses.prefix(cap) {
            lines.append("    - \(entry)")
        }
        if nearMisses.count > cap {
            lines.append("    … \(nearMisses.count - cap) more")
        }
        return lines
    }

    private static func coverageLines(_ coverageHints: CoverageHints?) -> [String]? {
        guard let coverageHints else { return nil }
        let classes = formatBuckets(coverageHints.inputClasses)
        let boundaries = formatBuckets(coverageHints.boundaryHits)
        return ["  Coverage: classes=\(classes), boundaries=\(boundaries)"]
    }

    private static func formatBuckets(_ buckets: [String: Int]) -> String {
        if buckets.isEmpty { return "{}" }
        // Sorted by key for stable output across runs.
        let parts = buckets
            .sorted { $0.key < $1.key }
            .map { "\($0.key): \($0.value)" }
        return "{\(parts.joined(separator: ", "))}"
    }
}
