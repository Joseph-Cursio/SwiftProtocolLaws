import PropertyBased

/// Run `Sequence` protocol laws over `Value` (PRD §4.3).
///
/// Default `laws: .all` first runs the inherited `IteratorProtocol` suite per
/// PRD §4.3 inheritance semantics; `.ownOnly` skips it.
///
/// Sequence laws (returned in this order after the inherited suite, when run):
/// - `underestimatedCountLowerBound` (Strict) — the iterator yields at least
///   `underestimatedCount` elements.
/// - `multiPassConsistency` (Conventional) — two fresh iterators yield the
///   same elements in the same order. Suppressed by `passing: .singlePass`.
/// - `makeIteratorIndependence` (Conventional) — calling `makeIterator()`
///   does not perturb prior iterators or the sequence's observable state.
///   Suppressed by `passing: .singlePass`.
@discardableResult
public func checkSequenceProtocolLaws<Value: Sequence & Sendable, Shrinker: SendableSequenceType>(
    for type: Value.Type = Value.self,
    using generator: Generator<Value, Shrinker>,
    options: LawCheckOptions = LawCheckOptions(),
    sequenceOptions: SequenceLawOptions = SequenceLawOptions(),
    laws: LawSelection = .all
) async throws -> [CheckResult]
where Value.Element: Equatable & Sendable {
    var results: [CheckResult] = []
    if laws == .all {
        results.append(contentsOf: await collectInheritedIterator(
            for: type,
            using: generator,
            options: options
        ))
    }
    let runner = TrialRunner(
        trials: options.budget.trialCount,
        seed: options.seed,
        generator: generator,
        environment: .current,
        suppressions: options.suppressions
    )
    results.append(await checkUnderestimatedCountLowerBound(runner: runner))
    if sequenceOptions.passing == .multiPass {
        results.append(await checkMultiPassConsistency(runner: runner))
        results.append(await checkMakeIteratorIndependence(runner: runner))
    }
    try ProtocolLawViolation.throwIfViolations(in: results, enforcement: options.enforcement)
    return results
}

private func collectInheritedIterator<S: Sequence & Sendable, Sh: SendableSequenceType>(
    for type: S.Type,
    using generator: Generator<S, Sh>,
    options: LawCheckOptions
) async -> [CheckResult]
where S.Element: Equatable & Sendable {
    let inheritedOptions = LawCheckOptions(
        budget: options.budget,
        enforcement: .default,
        seed: options.seed,
        suppressions: options.suppressions
    )
    do {
        return try await checkIteratorProtocolLaws(
            for: type,
            using: generator,
            options: inheritedOptions
        )
    } catch let violation as ProtocolLawViolation {
        return violation.results
    } catch {
        return []
    }
}

private func checkUnderestimatedCountLowerBound<
    S: Sequence & Sendable, Sh: SendableSequenceType
>(
    runner: TrialRunner<S, Sh>
) async -> CheckResult
where S.Element: Equatable & Sendable {
    await runner.runPerTrial(
        protocolLaw: "Sequence.underestimatedCountLowerBound",
        tier: .strict
    ) { gen, rng in
        let sample = gen.run(using: &rng)
        let underestimated = sample.underestimatedCount
        let cap = iterationCap(for: sample, floor: underestimated)
        var iterator = sample.makeIterator()
        var pulled = 0
        while pulled < cap, iterator.next() != nil { pulled += 1 }
        if pulled < underestimated {
            return .violation(
                counterexample: "sequence \(sample) reported underestimatedCount = "
                    + "\(underestimated) but iterator yielded only \(pulled) elements "
                    + "before returning nil"
            )
        }
        return .pass
    }
}

private func checkMultiPassConsistency<S: Sequence & Sendable, Sh: SendableSequenceType>(
    runner: TrialRunner<S, Sh>
) async -> CheckResult
where S.Element: Equatable & Sendable {
    await runner.runPerTrial(
        protocolLaw: "Sequence.multiPassConsistency",
        tier: .conventional
    ) { gen, rng in
        let sample = gen.run(using: &rng)
        let cap = iterationCap(for: sample, floor: sample.underestimatedCount)
        let pass1 = collect(sample, cap: cap)
        let pass2 = collect(sample, cap: cap)
        if pass1 == pass2 { return .pass }
        return .violation(
            counterexample: "sequence \(sample) yielded different elements on "
                + "two fresh iterators (pass1 = \(pass1.prefix(8))…, "
                + "pass2 = \(pass2.prefix(8))…)"
        )
    }
}

private func checkMakeIteratorIndependence<S: Sequence & Sendable, Sh: SendableSequenceType>(
    runner: TrialRunner<S, Sh>
) async -> CheckResult
where S.Element: Equatable & Sendable {
    await runner.runPerTrial(
        protocolLaw: "Sequence.makeIteratorIndependence",
        tier: .conventional
    ) { gen, rng in
        let sample = gen.run(using: &rng)
        let cap = iterationCap(for: sample, floor: sample.underestimatedCount)

        // Baseline: full iteration without any interleaving.
        let baseline = collect(sample, cap: cap)
        let half = baseline.count / 2

        // Interleave: pull half through A, make B and exhaust it, then drain A.
        var iteratorA = sample.makeIterator()
        var prefixA: [S.Element] = []
        for _ in 0..<half {
            guard let element = iteratorA.next() else { break }
            prefixA.append(element)
        }
        var iteratorB = sample.makeIterator()
        var fullB: [S.Element] = []
        var pulled = 0
        while pulled < cap, let element = iteratorB.next() {
            fullB.append(element)
            pulled += 1
        }
        var suffixA: [S.Element] = []
        var pulledA = prefixA.count
        while pulledA < cap, let element = iteratorA.next() {
            suffixA.append(element)
            pulledA += 1
        }
        let interleavedA = prefixA + suffixA
        if interleavedA != baseline {
            return .violation(
                counterexample: "interleaving makeIterator() perturbed iterator A on "
                    + "\(sample): baseline = \(baseline.prefix(8))…, "
                    + "interleavedA = \(interleavedA.prefix(8))…"
            )
        }
        if fullB != baseline {
            return .violation(
                counterexample: "second iterator on \(sample) yielded different elements "
                    + "from baseline: baseline = \(baseline.prefix(8))…, "
                    + "fullB = \(fullB.prefix(8))…"
            )
        }
        return .pass
    }
}

private func collect<S: Sequence>(_ sample: S, cap: Int) -> [S.Element] {
    var iterator = sample.makeIterator()
    var collected: [S.Element] = []
    var pulled = 0
    while pulled < cap, let element = iterator.next() {
        collected.append(element)
        pulled += 1
    }
    return collected
}

/// Cap on per-trial iterator pulls. The floor protects against runaway
/// iterators that under-report their `underestimatedCount`.
private func iterationCap<S: Sequence>(for sample: S, floor: Int) -> Int {
    let underestimated = sample.underestimatedCount
    let bumped = Swift.max(underestimated, floor) &* 100
    return Swift.max(10_000, bumped)
}
