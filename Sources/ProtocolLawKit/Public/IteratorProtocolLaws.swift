import PropertyBased

/// Run `IteratorProtocol` protocol laws (PRD §4.3).
///
/// Parameterized over the host `Sequence` rather than the iterator itself: the
/// check makes a fresh iterator inside each trial via `makeIterator()`. This
/// keeps the API Sendable-clean (most iterators are reference-shaped and not
/// Sendable, but the sequence value is) and matches how iterators are used in
/// idiomatic Swift code.
///
/// Laws (both Conventional tier — see PRD §4.3 IteratorProtocol):
/// - **Termination stability**: once `next()` returns `nil`, subsequent calls
///   also return `nil` (the iterator stays exhausted).
/// - **Single-pass yield**: an iterator over a finite sequence terminates
///   within a generous cap of its source's `underestimatedCount`. An iterator
///   that loops forever or resets after `nil` triggers this check.
@discardableResult
public func checkIteratorProtocolLaws<S: Sequence & Sendable, Sh: SendableSequenceType>(
    for type: S.Type = S.self,
    using generator: Generator<S, Sh>,
    options: LawCheckOptions = LawCheckOptions()
) async throws -> [CheckResult]
where S.Element: Equatable & Sendable {
    let runner = TrialRunner(
        trials: options.budget.trialCount,
        seed: options.seed,
        generator: generator,
        environment: .current,
        suppressions: options.suppressions
    )
    let results = [
        await checkTerminationStability(runner: runner),
        await checkSinglePassYield(runner: runner)
    ]
    try ProtocolLawViolation.throwIfViolations(in: results, enforcement: options.enforcement)
    return results
}

private func checkTerminationStability<S: Sequence & Sendable, Sh: SendableSequenceType>(
    runner: TrialRunner<S, Sh>
) async -> CheckResult
where S.Element: Equatable & Sendable {
    await runner.runPerTrial(
        protocolLaw: "IteratorProtocol.terminationStability",
        tier: .conventional
    ) { gen, rng in
        let sample = gen.run(using: &rng)
        var iterator = sample.makeIterator()
        let cap = iterationCap(for: sample)
        var pulled = 0
        while pulled < cap, iterator.next() != nil { pulled += 1 }
        if pulled == cap {
            // Couldn't observe termination within cap — single-pass-yield's
            // problem to flag. This law is vacuously satisfied for the trial.
            return .pass
        }
        // First nil observed. Two more calls must also be nil.
        let secondNil = iterator.next()
        let thirdNil = iterator.next()
        if secondNil != nil || thirdNil != nil {
            return .violation(
                counterexample: "iterator over \(sample) returned nil then "
                    + "yielded another element on a subsequent call "
                    + "(secondNil=\(String(describing: secondNil)), "
                    + "thirdNil=\(String(describing: thirdNil)))"
            )
        }
        return .pass
    }
}

private func checkSinglePassYield<S: Sequence & Sendable, Sh: SendableSequenceType>(
    runner: TrialRunner<S, Sh>
) async -> CheckResult
where S.Element: Equatable & Sendable {
    await runner.runPerTrial(
        protocolLaw: "IteratorProtocol.singlePassYield",
        tier: .conventional
    ) { gen, rng in
        let sample = gen.run(using: &rng)
        var iterator = sample.makeIterator()
        let cap = iterationCap(for: sample)
        var pulled = 0
        while pulled < cap, iterator.next() != nil { pulled += 1 }
        if pulled == cap {
            return .violation(
                counterexample: "iterator over \(sample) yielded \(pulled) elements "
                    + "without terminating (cap based on underestimatedCount = "
                    + "\(sample.underestimatedCount)); suspected infinite loop or "
                    + "post-`nil` reset"
            )
        }
        return .pass
    }
}

/// Generous upper bound on next()-call count per trial. Allows iterators that
/// produce more than `underestimatedCount` elements (the bound is a *lower*
/// bound by Sequence's contract) but rejects those that run away.
private func iterationCap<S: Sequence>(for sample: S) -> Int {
    let underestimated = sample.underestimatedCount
    return Swift.max(10_000, underestimated &* 100)
}
