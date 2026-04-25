import PropertyBased

/// Run `Collection` protocol laws over `Value` (PRD §4.3).
///
/// Default `laws: .all` first runs the inherited `Sequence` suite (which
/// itself chains the `IteratorProtocol` suite). Pass `.ownOnly` to skip
/// inherited laws.
///
/// Collection laws:
/// - `countConsistency` (Strict) — `count` matches the number of iterated
///   elements.
/// - `indexValidity` (Strict) — every index reachable by `index(after:)` from
///   `startIndex` is `< endIndex`, dereferences without crash, and matches
///   the corresponding element from sequence iteration.
/// - `nonMutation` (Conventional) — iterating does not perturb subsequent
///   passes. Trivially passes for value-type collections; meaningful for
///   reference-type collections that hold shared mutable state (relaxed for
///   lazy / view-like wrappers — see PRD §4.3).
@discardableResult
public func checkCollectionProtocolLaws<Value: Collection & Sendable, Shrinker: SendableSequenceType>(
    for type: Value.Type = Value.self,
    using generator: Generator<Value, Shrinker>,
    options: LawCheckOptions = LawCheckOptions(),
    sequenceOptions: SequenceLawOptions = SequenceLawOptions(),
    laws: LawSelection = .all
) async throws -> [CheckResult]
where Value.Element: Equatable & Sendable {
    var results: [CheckResult] = []
    if laws == .all {
        results.append(contentsOf: await collectInheritedSequence(
            for: type,
            using: generator,
            options: options,
            sequenceOptions: sequenceOptions
        ))
    }
    let runner = TrialRunner(
        trials: options.budget.trialCount,
        seed: options.seed,
        generator: generator,
        environment: .current,
        suppressions: options.suppressions
    )
    results.append(contentsOf: [
        await checkCountConsistency(runner: runner),
        await checkIndexValidity(runner: runner),
        await checkNonMutation(runner: runner)
    ])
    try ProtocolLawViolation.throwIfViolations(in: results, enforcement: options.enforcement)
    return results
}

private func collectInheritedSequence<C: Collection & Sendable, Sh: SendableSequenceType>(
    for type: C.Type,
    using generator: Generator<C, Sh>,
    options: LawCheckOptions,
    sequenceOptions: SequenceLawOptions
) async -> [CheckResult]
where C.Element: Equatable & Sendable {
    let inheritedOptions = LawCheckOptions(
        budget: options.budget,
        enforcement: .default,
        seed: options.seed,
        suppressions: options.suppressions
    )
    do {
        return try await checkSequenceProtocolLaws(
            for: type,
            using: generator,
            options: inheritedOptions,
            sequenceOptions: sequenceOptions
        )
    } catch let violation as ProtocolLawViolation {
        return violation.results
    } catch {
        return []
    }
}

private func checkCountConsistency<C: Collection & Sendable, Sh: SendableSequenceType>(
    runner: TrialRunner<C, Sh>
) async -> CheckResult
where C.Element: Equatable & Sendable {
    await runner.runPerTrial(
        protocolLaw: "Collection.countConsistency",
        tier: .strict
    ) { gen, rng in
        let sample = gen.run(using: &rng)
        let reportedCount = sample.count
        // Count by hand — `Array(sample)` would trap before we get to compare
        // when `count` lies (which is exactly the case we're trying to detect).
        let cap = Swift.max(reportedCount &+ 1, 10_000)
        let iteratedCount = manualIteratedCount(of: sample, cap: cap)
        if reportedCount == iteratedCount { return .pass }
        return .violation(
            counterexample: "collection \(sample) reported count = \(reportedCount) "
                + "but iteration yielded \(iteratedCount) elements"
        )
    }
}

private func checkIndexValidity<C: Collection & Sendable, Sh: SendableSequenceType>(
    runner: TrialRunner<C, Sh>
) async -> CheckResult
where C.Element: Equatable & Sendable {
    await runner.runPerTrial(
        protocolLaw: "Collection.indexValidity",
        tier: .strict
    ) { gen, rng in
        let sample = gen.run(using: &rng)
        // Walk via index(after:) and compare each subscripted element to a
        // manual iterator pass. Hand-rolled to avoid `Array(c)` trapping when
        // a sibling law (countConsistency) is being violated.
        let iterated = manualCollect(from: sample)
        var index = sample.startIndex
        var subscripted: [C.Element] = []
        let cap = iterated.count &+ 1
        var steps = 0
        while index != sample.endIndex {
            if steps > cap {
                return .violation(
                    counterexample: "collection \(sample) index walk exceeded \(cap) "
                        + "steps without reaching endIndex — index(after:) likely "
                        + "doesn't advance"
                )
            }
            subscripted.append(sample[index])
            index = sample.index(after: index)
            steps += 1
        }
        if subscripted != iterated {
            return .violation(
                counterexample: "collection \(sample) sequence iteration "
                    + "yielded \(iterated.prefix(8))… but index walk yielded "
                    + "\(subscripted.prefix(8))…"
            )
        }
        return .pass
    }
}

// Iterating over a value-type collection produces a copy and cannot mutate the
// original observable state through generic dispatch — this check is
// structurally unviolable for those. It's meaningful for reference-type
// collections that hold shared state. Comparable to Equatable.negationConsistency:
// kept as defensive coverage, conventional tier so it doesn't fail-CI on the
// common no-op case.
private func checkNonMutation<C: Collection & Sendable, Sh: SendableSequenceType>(
    runner: TrialRunner<C, Sh>
) async -> CheckResult
where C.Element: Equatable & Sendable {
    await runner.runPerTrial(
        protocolLaw: "Collection.nonMutation",
        tier: .conventional
    ) { gen, rng in
        let sample = gen.run(using: &rng)
        let pass1 = manualCollect(from: sample)
        let pass2 = manualCollect(from: sample)
        if pass1 != pass2 {
            return .violation(
                counterexample: "iterating collection \(sample) appears to perturb "
                    + "its observable state: pass1 = \(pass1.prefix(8))…, "
                    + "pass2 = \(pass2.prefix(8))…"
            )
        }
        return .pass
    }
}

/// Iterate via Sequence's `makeIterator()` until `nil`, capped to defend
/// against runaway iterators. Avoids `Array(c)` which traps when `c.count`
/// disagrees with iteration — the precise condition `countConsistency`
/// exists to catch.
private func manualCollect<S: Sequence>(from sample: S, cap: Int = 100_000) -> [S.Element] {
    var iterator = sample.makeIterator()
    var collected: [S.Element] = []
    var pulled = 0
    while pulled < cap, let element = iterator.next() {
        collected.append(element)
        pulled += 1
    }
    return collected
}

private func manualIteratedCount<S: Sequence>(of sample: S, cap: Int) -> Int {
    var iterator = sample.makeIterator()
    var count = 0
    while count < cap, iterator.next() != nil { count += 1 }
    return count
}
