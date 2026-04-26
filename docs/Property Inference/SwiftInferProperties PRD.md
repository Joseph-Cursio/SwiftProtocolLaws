# Product Requirements Document

## SwiftInferProperties: Type-Directed Property Inference for Swift

**Version:** 0.2 Draft
**Status:** Proposal
**Audience:** Open Source Contributors, Swift Ecosystem
**Depends On:** SwiftProtocolLaws (ProtocolLawKit + ProtoLawMacro)

**Changes from v0.1:** See Appendix A. v0.2 incorporates pushback from three external reviewers (collected in `docs/Property Inference/*critique of PRD.md`) and the parent project's v0.3 single-backend-by-design decision.

-----

## 1. Overview

### 1.1 Context

SwiftProtocolLaws addresses the lowest-hanging fruit in automated property testing: if a type declares a protocol, verify that the implementation satisfies the protocol's semantic laws. That project is intentionally scoped to the *explicit* — conformances the developer has already declared.

SwiftInferProperties addresses what comes next: the *implicit*. Properties that are meaningful and testable, but are not encoded in any protocol declaration. They live in the structure of function signatures, in the relationships between functions, and in the patterns visible in existing unit tests.

### 1.2 Two Contributions

This document proposes **SwiftInferProperties**, a Swift package delivering two contributions:

- **Contribution 1 — TemplateEngine**: A library of named property templates matched against function signatures via SwiftSyntax, emitting candidate property tests for human review. Templates cover both pairwise inference (round-trip, commutativity) and algebraic-structure detection (semilattices, reducers) — not just data-structure properties.
- **Contribution 2 — TestLifter**: A tool that analyzes existing XCTest and Swift Testing unit test suites, identifies structural patterns in the tests, and suggests generalized property tests derived from those patterns.

Both contributions produce *suggestions for human review*, not silently executed tests. The developer is always in the loop.

### 1.3 Philosophy: High Precision, Low Recall

SwiftInferProperties prioritizes **precision over coverage**. Three excellent suggestions beat thirty mediocre ones. Every design tradeoff in this document — confidence tiering, sampling-before-suggesting, mandatory cross-validation between TemplateEngine and TestLifter, the `.todo` generator forcing function — is downstream of this commitment.

The failure mode being prevented is "Clippy for tests": a tool that nags developers with low-signal suggestions until they stop reading the output. The failure mode being accepted is missing some real properties that a more aggressive tool would have caught.

This is a deliberate calibration: structural inference is inherently noisy, and trust burns down faster than it rebuilds. The tool stays conservative until validated against real codebases (see §10 Success Criteria).

-----

## 2. Problem Statement

### 2.1 Properties Beyond Protocols

Protocol law testing, as provided by SwiftProtocolLaws, covers a well-defined and bounded space. But most of the interesting correctness properties of a codebase are not expressible as protocol laws. Consider:

```swift
func normalize(_ input: String) -> String
func compress(_ data: Data) -> Data
func decompress(_ data: Data) -> Data
func applyDiscount(_ price: Decimal, _ rate: Decimal) -> Decimal
```

None of these functions declare any protocol that implies testable properties. Yet:

- `normalize` is *plausibly* idempotent: `normalize(normalize(x)) == normalize(x)`
- `compress`/`decompress` *plausibly* form a round-trip pair: `decompress(compress(x)) == x`
- `applyDiscount` *plausibly* preserves ordering: if `a < b` then `applyDiscount(a, r) < applyDiscount(b, r)`

These properties are discoverable from *structure* — function names, type signatures, and relationships between functions — without requiring the developer to have written any tests at all. The hedging in "plausibly" is load-bearing: see §2.4.

### 2.2 The Unit Test as an Underused Signal

Most Swift codebases with meaningful test coverage have unit tests that implicitly encode structural knowledge. A test like:

```swift
func testRoundTrip() {
    let original = MyData(value: 42)
    let encoded = encoder.encode(original)
    let decoded = decoder.decode(encoded)
    XCTAssertEqual(original, decoded)
}
```

encodes the round-trip property for one specific input. The general property — `decode(encode(x)) == x` for *all* `x` — is right there, but it takes a deliberate step to lift it. Most developers don't take that step because nothing prompts them to and the activation energy is nonzero.

### 2.3 The Gap SwiftInferProperties Fills

SwiftProtocolLaws handles: *"you declared a protocol, does your implementation honor its laws?"*

SwiftInferProperties handles: *"given what your code looks like and what your tests say, what properties are you implicitly claiming?"*

Together they cover the automated end of the property inference spectrum, from explicit protocol contracts down through structural inference to test-guided generalization.

### 2.3.1 Why this is novel territory

No mainstream language ships a comparable inference layer today. Haskell's QuickCheck requires manual property definitions; `quickcheck-classes` encodes typeclass laws but developers must opt in. Java's EvoSuite generates tests automatically and mines assertions from observed behavior, but does not infer algebraic laws or generalize across domains. Daikon infers numeric/structural invariants dynamically but does not produce property-based tests. Refinement-type systems (Liquid Haskell, F*) require annotations.

Swift's design gives us structural hooks no other ecosystem combines: protocol conformances expose explicit semantic laws (handled by SwiftProtocolLaws), value semantics make sampling deterministic, SwiftSyntax provides AST access without a custom parser, and modern PBT libraries (`swift-property-based`) integrate cleanly with Swift Testing. The combination makes signature-driven inference tractable in Swift in a way it isn't elsewhere.

This is positioning context, not a marketing claim — the rest of this document treats SwiftInferProperties as a conservative, precision-prioritizing tool, not a "first of its kind" pitch.

### 2.4 Semantic Ambiguity in Inference

Names lie. Type shapes mislead. Test structure can encode accidental properties that don't generalize. Three examples:

- `normalize` is often idempotent — but locale-sensitive Unicode normalization, lossy quantization, and cache-warming side effects all produce non-idempotent functions named `normalize`.
- `merge(a, b) -> Config` looks commutative — but most production `merge` functions are left-biased and `merge(a, b) != merge(b, a)`.
- `XCTAssertEqual(f(a, b), f(b, a))` in a unit test looks like a commutativity check — but the developer may have written it because they *suspect* commutativity and want a smoke test, not because it's guaranteed.

SwiftInferProperties addresses semantic ambiguity through three mechanisms:

1. **Type signatures gate candidacy; names only escalate confidence.** A function is a candidate for idempotence if its signature is `T → T`. Its name moves the candidate from `Possible` to `Likely`. The name alone never produces a candidate, and the name alone never reaches `Strong`.
2. **Sampling before surfacing.** Every `Likely` and `Strong` suggestion is run with a small generator (default: 25 inputs) before being emitted. Counterexamples filter the suggestion out. See §5.5.
3. **Cross-validation.** When TemplateEngine and TestLifter independently infer the same property, confidence is boosted. When only one infers it, confidence is capped. See §5.6.

-----

## 3. Goals and Non-Goals

### Goals

- Identify candidate properties from function signatures without requiring any developer annotation
- Surface round-trip pairs, idempotence candidates, and other algebraic patterns through structural analysis
- Analyze existing unit test suites and suggest lifted property tests
- **Explainability:** every suggestion includes the evidence and reasoning behind it (template matched, signals fired with weights, sampling result, originating test if applicable). A developer must be able to evaluate a suggestion without reading SwiftInferProperties' source code.
- Produce human-reviewable output with clear provenance and confidence indicators
- Integrate with SwiftProtocolLaws' `PropertyBackend` abstraction for test execution
- Operate as a CLI discovery tool, a compiler plugin, or both
- Persist developer rejection decisions across runs (no re-emitting suppressed suggestions)

### Non-Goals

- Automatically executing inferred properties without human review
- Replacing unit tests or SwiftProtocolLaws protocol law checks
- Full runtime invariant inference (Daikon-style instrumentation)
- Stateful / model-based test generation (separate project scope; see §11 Open Question 7 for a possible v1.1 carve-out)
- Correctness guarantees on inferred properties — all output is probabilistic suggestion
- Cross-module inference in v1 (see §7.1)

-----

## 4. Confidence Model

SwiftInferProperties assigns every suggestion a confidence tier. This is surfaced in all output and governs how aggressively suggestions are promoted.

| Tier   | Label        | Precision target | Default visibility | Meaning                                          |
|--------|--------------|------------------|--------------------|--------------------------------------------------|
| High   | `✓ Strong`   | ≥ 90%            | Shown              | Type evidence + name evidence + sampling pass + (TemplateEngine ∩ TestLifter agreement OR no other corroboration needed for this template). |
| Medium | `~ Likely`   | ≥ 70%            | Shown              | Type evidence + (name evidence OR test evidence) + sampling pass. |
| Low    | `? Possible` | unbounded        | Hidden (`--all`)   | Type evidence only, or contested signals. Opt-in. |

**Precision targets are aspirational calibration anchors, not contractual guarantees.** They give the validation suite (§10) something concrete to measure: if benchmark runs show Strong suggestions are accepted at <90%, the template-by-template scoring weights need to be re-tuned, not the tier definitions.

Confidence is **computed**, not assigned. Templates declare what evidence they require and what signals they accept; the §5.3.1 scoring model produces the tier from accumulated evidence. Template authors do not write `confidence: .strong` — they write the criteria that earn it.

All suggestions include:

- The property template matched
- The evidence that triggered the match (each signal with its weight)
- The specific functions or tests involved (with file:line provenance)
- The sampling result (e.g., `sampled 25 inputs, 0 counterexamples`)
- A reproducible seed for the sampling run

Counterexamples found during sampling **filter the suggestion out** rather than appearing in the emitted stub. The user only sees suggestions that survived sampling. (Filtered candidates are available via `--show-rejected` for debugging.)

-----

## 5. Contribution 1: TemplateEngine

### 5.1 Description

TemplateEngine is a SwiftSyntax-based static analysis pipeline that scans Swift source files, matches function signatures and naming patterns against a registry of named property templates, runs lightweight sampling against surviving candidates, and emits candidate property test stubs.

### 5.2 Property Template Registry

The registry is the intellectual core of TemplateEngine. Each entry defines:

- A **type pattern** (necessary): the function signature shape that makes a function a candidate at all
- **Name signals** (escalators): naming heuristics that move the candidate up the confidence ladder; never sufficient on their own
- **Sampling test**: how the candidate is validated at low trial budget before surfacing
- **Property test body** to emit
- **Interaction warnings** with other templates

Within each template below, the type pattern alone produces at most a `Possible` suggestion. Name signals can escalate to `Likely`. Cross-validation with TestLifter or strong-form name matches escalate to `Strong`.

#### Round-Trip

**Type pattern:** Two functions `f: T → U` and `g: U → T` in the same module, with both `T: Equatable`. *Necessary.*

**Name signals:** known inverse pairs (`encode`/`decode`, `serialize`/`deserialize`, `compress`/`decompress`, `encrypt`/`decrypt`, `parse`/`format`, `push`/`pop`, `insert`/`remove`, `open`/`close`). Escalator only; the type pattern must hold first.

**Sampling test:** generate 25 `T` values, check `g(f(t)) == t` for all of them.

**Emitted property:**

```swift
// Template: round-trip
// Confidence: Strong (score 0.91)
// Signals: type inversion T↔U (+0.4), name pair encode/decode (+0.4), same file (+0.1)
// Sampling: 25 inputs, 0 counterexamples (seed: 0x9F2C8B14)
// Evidence: encode(_:) -> Data (MyType.swift:14), decode(_:) -> MyType (MyType.swift:22)
@Test func roundTripEncoding() async {
    await propertyCheck(input: Gen.derived(MyType.self)) { value in
        #expect(try decode(encode(value)) == value)
    }
}
```

#### Idempotence

**Type pattern:** A function `f: T → T` with `T: Equatable`. *Necessary.*

**Name signals:** `normalize`, `canonicalize`, `trim`, `flatten`, `sort`, `deduplicate`, `sanitize`, `format`. Escalator only.

**Sampling test:** generate 25 `T` values, check `f(f(t)) == f(t)` for all of them.

#### Commutativity

**Type pattern:** A function `f: (T, T) → U` with `U: Equatable`. *Necessary.*

**Name signals:** `merge`, `combine`, `union`, `add`, `plus`, `intersect`, `meet`, `join`. Escalator only.

**Anti-signals (block escalation):** `subtract`, `difference`, `divide`, `apply`, `prepend`, `append`. The presence of an anti-signal name caps the suggestion at `Possible`.

**Sampling test:** generate 25 `(T, T)` pairs, check `f(a, b) == f(b, a)` for all of them.

#### Associativity

**Type pattern:** A function `f: (T, T) → T` with `T: Equatable`. *Necessary.*

**Name signals:** same as commutativity. Often suggested alongside.

**Sampling test:** generate 15 `(T, T, T)` triples, check `f(f(a, b), c) == f(a, f(b, c))` for all of them.

#### Identity Element

**Type pattern:** A binary operation `f: (T, T) → T` with `T: Equatable` plus a candidate identity element. *Necessary.*

Identity-element candidates, evaluated in priority order:

1. A static value of type `T` named one of `{ zero, empty, identity, none, default }` — strong signal.
2. A parameter-less initializer `T()` whose result is consistent across calls (validated via sampling) — moderate signal. Captures `String()`, `[Element]()`, `Set<Element>()`, `Config()` (all-defaults), and custom monoid types whose `init()` returns the neutral value.
3. The same value (static or `T()`) used as the seed of `reduce(_:_:)` calls elsewhere in the module — strong signal that the type is already being treated monoidally by the codebase.

A type with both signals 1 and 3 is a high-confidence monoid candidate; this composes with the §5.9 upstream-loop suggestions.

Comment-based detection ("// neutral element", `/// the identity for combine`) is **not** used in v1; see §11 Open Question 8.

**Sampling test:** generate 25 `T` values, check `f(t, identity) == t && f(identity, t) == t`.

#### Semilattice / Idempotent-Commutative-Associative Merge

> **New in v0.2.** Configuration merging, conflict resolution, feature-flag composition, and "take the max" / "take the min" patterns are all (join- or meet-) semilattices. Detecting them as a single algebraic-structure candidate — rather than emitting three independent Idempotence + Commutativity + Associativity suggestions on the same function — keeps the suggestion budget meaningful and matches how developers think about these operations.

**Type pattern:** `f: (T, T) → T` with `T: Equatable`. *Necessary.*

**Name signals (strong-form):** `merge`, `merged`, `merging(with:)`, `union`, `unioned`, `intersect`, `intersection`, `combine`, `combined`, `coalesce`, `meet`, `join`, `joined`. Any of these escalate to Likely; absent a name signal, the candidate caps at Possible.

**Anti-signals (cap at Possible):** `subtract`, `difference`, `apply`, `prepend`, `append` — same as plain Commutativity.

**Sampling test:** the candidate must pass **all three** laws at the sampling stage:
- Idempotence: `f(t, t) == t` over 25 `T` values
- Commutativity: `f(a, b) == f(b, a)` over 25 `(T, T)` pairs
- Associativity: `f(f(a, b), c) == f(a, f(b, c))` over 15 `(T, T, T)` triples

Partial passes — e.g., commutative + associative but not idempotent — fall back to emitting the relevant scalar templates (Commutativity, Associativity) without the semilattice classification.

**Subsumption rule:** when this template fires for a function, the standalone Idempotence, Commutativity, and Associativity suggestions on the same function are suppressed. The semilattice suggestion subsumes them with a single explanation.

**Identity-bearing semilattices:** when `T` also has an identity (§5.2 Identity Element fires), the suggestion is annotated as a *bounded semilattice* (equivalently, an idempotent commutative monoid), and §5.9's upstream-loop suggestion fires to consider `SetAlgebra` conformance.

**Emitted property:** three (or four with identity) `@Test` functions in one block, sharing a header that names the algebraic classification:

```swift
// Template: semilattice (idempotent + commutative + associative merge)
// Confidence: Strong (score 0.92)
// Signals: type (T, T)→T (+0.4), strong-form name "merge" (+0.4), sampling 65/65 passed (+0.1)
// Evidence: merge(_:_:) -> Config (Config.swift:31)
// Note: a bounded semilattice (Config.empty acts as identity) — see SetAlgebra suggestion below.

@Test func mergeIsIdempotent() async { ... }
@Test func mergeIsCommutative() async { ... }
@Test func mergeIsAssociative() async { ... }
```

#### Reducer / Event Application

> **New in v0.2.** Catches the algebraic backbone of state machines, event sourcing, SwiftUI/TCA reducers, and analytics aggregation. Reducers are routinely *presumed* pure but not always *actually* pure; the v1 Reducer template focuses on what's testable from a single function: determinism. Richer reducer-specific properties (commutativity of independent events, idempotence of normalize-events) are annotation-driven and ship in v1.1.

**Type pattern:** Functions with one of these shapes, where `S: Equatable`:

- `func reduce(_ state: S, _ event: E) -> S`
- `func reduce(into state: inout S, _ event: E)`
- `mutating func apply(_ event: E)` on a value type with `Equatable` self
- `func apply(_ event: E) -> Self` returning the same value type

*Necessary.*

**Name signals:** `reduce`, `apply`, `step`, `dispatch`, `handle`, `process`, `fold`. Strong-form when paired with the type pattern.

**Property inferred (v1):** **Determinism** — `reduce(s, e)` produces the same result across repeated calls. This is the lowest-bar reducer property and the most often violated one: hidden state, time-of-day, randomness, and side-effecting telemetry calls inside reducers are recurring bugs in real Swift codebases (especially in TCA-style architectures where the architecture *promises* purity).

**Sampling test:** generate 25 `(S, E)` pairs; for each, call `reduce(s, e)` twice and assert equal.

**Anti-signals:** the function body references `Date()`, `Date.now`, `URLSession`, `random()`, or other APIs flagged by §6.6's flakiness gate. Tripping an anti-signal does **not** drop the suggestion — instead, the candidate emits at Possible tier with an explanatory note, since the flakiness signal *is* the property failing and the developer should evaluate whether the non-determinism is intentional. (Most reducers should be deterministic; the few that legitimately aren't deserve an explicit `// swiftinfer: reject reducer` marker.)

**Annotation extensions (v1.1, not in v1):**

- `@CheckProperty(.reducerCommutative(events: [.foo, .bar]))` — commutativity of specified independent events
- `@CheckProperty(.reducerIdempotent(event: .normalize))` — idempotence of a specific event

These extensions are scoped to v1.1 because they require user assertions about which events are independent or idempotent — information not derivable from signature alone.

#### Monotonicity

> **Demoted in v0.2.** v0.1 emitted Monotonicity at `Likely` from signature alone. Reviewer feedback was unanimous: most numeric-input functions are not monotonic, and the "adjust direction if needed" comment in v0.1's emitted stub was ducking half the property's definition. v0.2 restricts this template heavily.

**Type pattern:** A function `f: T → U` where `T, U: Comparable`. *Necessary.*

**Name signals:** `scale`, `apply`, `transform`, `weight`. Escalator only — but in v0.2, name signals **do not escalate beyond `Possible`** for monotonicity. The only paths to `Likely`+:

1. **TestLifter corroboration:** at least 2 lifted ordering tests (§6.2 Assert-Ordering-Preserved) on the same function with structurally distinct inputs.
2. **Explicit annotation:** `@CheckProperty(.monotonic(.increasing))` or `.monotonic(.decreasing))` — direction is part of the annotation, not a runtime guess.

**Sampling test:** generate 25 `(T, T)` pairs where `a < b`, check that direction holds across all `f(a)`/`f(b)` pairs. The sampling itself determines direction (increasing/decreasing/non-monotone) when annotation is absent; non-monotone results filter the suggestion entirely.

This template ships in M6 rather than M4 (see §5.10) so the corroboration pipeline is in place before monotonicity emits anything.

#### Invariant Preservation

> **Annotation-required in v0.2.** v0.1 marked this as Low confidence by default; v0.2 makes it annotation-only because the search space is unbounded otherwise.

**Type pattern:** Any mutating or transforming function. *Too permissive on its own.*

**Required:** `@CheckProperty(.invariantPreservation(...))` annotation specifying the invariant predicate. The template never fires without annotation.

```swift
@CheckProperty(.invariantPreservation(beforeAfter: { stack, modified in modified.count == stack.count + 1 }))
mutating func append(_ value: Element)
```

### 5.3 Cross-Function Pairing Strategy

Naive cross-function pairing is O(n²). TemplateEngine avoids this through tiered filtering:

1. **Type filter (primary):** Only pair `f: T → U` with `g: U → T`. Applied first, eliminates most candidates.
2. **Naming filter (secondary):** Score pairs by known inverse name patterns; project-configurable synonyms (§5.8).
3. **Scope filter (tertiary):** Prefer pairs within the same type or file before considering module-wide pairs.
4. **User grouping (optional):** `@Discoverable(group: "serialization")` explicitly groups functions for pairing.

In practice, a module of 50 functions typically produces fewer than 10 candidate pairs after type filtering.

#### Overloaded functions

When a module has multiple `encode`/`decode` overloads, exact-type matching prevents combinatorial explosion. Given:

```swift
func encode(_ x: Foo) -> Data
func encode(_ x: Bar) -> Data
func decode(_ data: Data) -> Foo
func decode(_ data: Data) -> Bar
```

TemplateEngine emits exactly two pairs (`Foo`/`Foo`, `Bar`/`Bar`), not four. The pairing key is `(input-type, output-type)`, not just `(name, name)`. Generic overloads (`encode<T: Codable>`) require explicit bindings via `@LawGenerator(bindings: ...)` — same convention as ProtocolLawKit (parent project §4.4 Generic Conformances).

### 5.3.1 Scoring Model

Confidence is computed by an additive scoring model. Every signal has a documented weight; the total maps to a tier via fixed thresholds.

```
score = Σ signals
tier  = Strong    if score ≥ 0.85
        Likely    if score ≥ 0.55
        Possible  otherwise
```

Signals (representative; not exhaustive):

| Signal                                            | Weight | Notes                              |
|---------------------------------------------------|--------|------------------------------------|
| Type pattern matches (necessary)                  | +0.40  | Below threshold without this       |
| Strong-form name match (e.g., `encode`/`decode`)  | +0.40  | Per template's name list           |
| Weak-form name match (project-configured synonym) | +0.20  | See §5.8                           |
| Same file                                         | +0.10  | Cross-function pairs only          |
| Same type/extension                               | +0.10  | Cross-function pairs only          |
| TestLifter corroboration on same property         | +0.20  | See §5.6                           |
| Sampling pass at default budget                   | +0.10  | Required for ≥ Likely              |
| Sampling pass at high budget (250 inputs)         | +0.05  | Optional, opt-in via flag          |
| Anti-signal name match                            | -0.30  | Per template's anti-signal list    |
| Contradiction with another template (§5.4)        | -0.40  | Per contradiction table            |

Every emitted suggestion shows its score breakdown:

```
// Confidence: Likely (score 0.78)
// Signals:
//   + Type inversion T↔U                    +0.40
//   + Name pair encode/decode (strong-form) +0.40
//   - Anti-signal: function returns Result  -0.10
//   + Sampling: 25/25 passed                +0.10
```

This transparency is the single biggest trust-builder. A developer who disagrees with a suggestion can point at a specific signal weight and argue with it; an opaque tier label leaves them no recourse.

### 5.4 Contradiction Detection

When multiple templates are suggested for the same function, TemplateEngine checks for logical contradictions before emitting:

| Combination                            | Implication                  | Action                                   |
|----------------------------------------|------------------------------|------------------------------------------|
| Idempotent + Involutive                | `f` must be identity         | ⚠️ Warn; demote both to Possible          |
| Commutative + non-Equatable output     | Commutativity is untestable  | Drop commutativity suggestion             |
| Round-trip without `T: Equatable`      | Round-trip is untestable     | Drop round-trip suggestion                |
| Idempotent on binary op + Identity     | Suggests semilattice         | Note: consider conformance (§5.9)         |

This list is **curated, not exhaustive.** SwiftInferProperties does not aspire to soundness or completeness over a property algebra; new contradiction patterns require maintainer commits, not graph reasoning. (This mirrors the parent project's §5.6 stance on pattern warnings: a curated, named-pattern list is more maintainable than a half-working inference engine that occasionally surprises users.)

### 5.5 Sampling Before Suggesting

Every `Likely` and `Strong` candidate is run through a sampling stage **before** appearing in CLI output:

1. The candidate's required generators are derived (§6.4 priority order, shared with TestLifter).
2. The property body is executed with 25 inputs (configurable via `--sample-budget`).
3. If any input produces a counterexample, the suggestion is **dropped**, not surfaced.
4. The sampling seed is recorded and emitted with the surviving suggestion.

Why drop rather than warn? A counterexample isn't a low-confidence signal — it's a refutation. Showing the developer "this property looks plausible but here's a counterexample" wastes their time more than it helps; a refuted candidate should not have been a candidate.

The trade-off: candidates whose generators can't be derived skip sampling and **cap at `Possible`** (visible only with `--all`). This bias is intentional. Untested suggestions don't earn the precision targets in §4.

`--show-rejected` exposes the dropped candidates for debugging template authoring.

### 5.6 Cross-Validation with TestLifter

TemplateEngine and TestLifter run independently and merge results before output:

| TemplateEngine | TestLifter   | Merged confidence |
|----------------|--------------|-------------------|
| Strong         | Corroborates | Strong (boosted)  |
| Likely         | Corroborates | Strong            |
| Likely         | Silent       | Likely            |
| Likely         | Contradicts  | Possible + warning|
| Silent         | Strong       | Likely (capped)   |

A TestLifter-only suggestion **caps at `Likely`** in v0.2 — tests can encode accidental structure that doesn't generalize, and the corroborating signal of "the type signature also fits this property" is missing. This cap is conservative; it can be re-evaluated after benchmark validation (§10).

A direct contradiction (TemplateEngine suggests commutativity, TestLifter finds asymmetric examples in tests) drops the suggestion to `Possible` and emits an explanatory warning in the comment block, since the developer may want to see *why* the tool can't agree with itself.

### 5.6.1 Existing-Test Detection

Before emitting a suggestion, TemplateEngine checks whether an equivalent property test already exists in the project's test targets. If one does, the suggestion is suppressed.

**Equivalence is structural, not textual.** A test counts as covering an inferred property when its body matches the same `propertyCheck` shape over the same target functions. The detection runs SwiftSyntax over `Tests/**/*.swift`, scans for `propertyCheck`, `forAll`, and equivalent backend entry points, and indexes them by `(target function(s), property template)`. A hand-written test like:

```swift
@Test func myEncodingRoundTrips() async {
    await propertyCheck(input: Gen.derived(MyType.self)) { value in
        #expect(decode(encode(value)) == value)
    }
}
```

prevents TemplateEngine from re-suggesting round-trip on `(encode, decode)` for `MyType`. The function name doesn't have to match a SwiftInferProperties-generated stub — only the structural shape matters.

**Three categories of existing coverage are detected:**

1. **Property tests written by hand** (most common). Suppression with no warning.
2. **Property tests previously generated by SwiftInferProperties and adopted.** Detected via the auto-generated comment header (`// Template: round-trip`) which survives the developer's edits unless they intentionally strip it. Suppression with no warning.
3. **Unit tests that exercise the property on a single input.** Not equivalent — the property still generalizes beyond the unit case. SwiftInferProperties emits the suggestion with a note: `// Note: testRoundTrip in MyDataTests.swift:14 covers a single case; this property generalizes it.`

**Out of scope for v1:** semantic equivalence detection (e.g., recognizing that `XCTAssertEqual(encode(decode(x)), x)` and `XCTAssertEqual(decode(encode(x)), x)` are the same round-trip property in different forms). v1 detects structural matches only; semantic matching is a v1.1 candidate gated on benchmark false-positive rates.

### 5.7 Annotation API

Developers can guide TemplateEngine with lightweight annotations rather than waiting for automatic discovery:

```swift
@CheckProperty(.idempotent)
func normalize(_ input: String) -> String { ... }

@CheckProperty(.roundTrip, pairedWith: "decode")
func encode(_ value: MyType) -> Data { ... }

@CheckProperty(.monotonic(.increasing))
func applyMultiplier(_ x: Decimal) -> Decimal { ... }

@Discoverable(group: "serialization")
func decode(_ data: Data) -> MyType { ... }
```

Annotations work on:

- Primary type declarations
- **Extensions** of types (including extensions in different files than the primary declaration)
- Free functions
- Methods on protocol extensions

`@CheckProperty` triggers immediate stub generation for that function. `@Discoverable` groups functions for cross-function pairing without asserting a specific template.

#### Rejection markers

Once a developer dismisses a suggestion they don't want re-emitted on the next run, they record the dismissal at the call site:

```swift
// swiftinfer: reject roundTrip
func encode(_ x: Foo) -> Data { ... }
```

Rejections are per-template; a developer can reject `roundTrip` on a function while leaving `idempotence` to be re-suggested. The Discovery CLI honors these markers across runs and treats them as part of the project's source of truth (see also Open Question 6).

### 5.8 Project Configuration

A project-level `.swiftinfer.toml` (or equivalent) lets teams tune SwiftInferProperties without forking the registry:

```toml
[templates]
disable = ["monotonicity"]              # never suggest this template
boost   = ["roundTrip"]                 # raise threshold weights

[naming.synonyms]
encode    = ["serialize", "marshal", "toData"]
decode    = ["deserialize", "unmarshal", "fromData"]
normalize = ["canonicalize", "standardize"]

[output]
maxSuggestionsPerModule = 10            # hard cap, see §9
showPossibleByDefault   = false
```

Synonyms are additive over the built-in registry; teams can teach SwiftInferProperties their own domain vocabulary without contributing upstream. The cap on suggestions is a hard limit, not a recommendation: the engine sorts by score and stops emitting once the cap is reached, with a footer line indicating how many additional suggestions were suppressed.

### 5.9 Reinforcing the Upstream Loop

When an inferred property exactly matches a law from ProtocolLawKit's catalog, SwiftInferProperties **suggests conformance**, not a one-off property test:

```
// SwiftInferProperties: this looks like a Monoid
//   - merge(_:_:) is Likely commutative AND associative
//   - .empty is Likely the identity element
// Consider conforming MyType to AdditiveArithmetic and using ProtocolLawKit's
// checkAdditiveArithmeticProtocolLaws — the inherited laws cover all three
// properties above and more.
```

This deepens integration with the parent project: SwiftInferProperties is a discovery layer that funnels the developer back into ProtocolLawKit's checked, maintained law suites whenever the inferred properties happen to compose into a recognized algebraic structure.

The mappings ship as a small curated table; adding a new mapping requires a maintainer commit. This is not graph reasoning over the property algebra.

| Inferred structure                                           | Suggested conformance / tool                                            |
|--------------------------------------------------------------|-------------------------------------------------------------------------|
| Monoid (associative + identity)                              | Consider `AdditiveArithmetic` and ProtocolLawKit's law check            |
| Commutative monoid                                           | Consider `AdditiveArithmetic` and ProtocolLawKit's law check            |
| Bounded semilattice (idempotent commutative monoid)          | Consider `SetAlgebra` and ProtocolLawKit's `SetAlgebra` law check       |
| Total order (Comparable laws inferred from monotonic chains) | Consider `Comparable` and ProtocolLawKit's `Comparable` law check       |
| Round-trip pair (encode/decode-shaped)                       | Consider `Codable` and ProtocolLawKit's `Codable` round-trip law check  |
| Group (associative + identity + inverse)                     | No standard library protocol; emit standalone property tests            |
| Ring (two operations + distributivity)                       | No standard library protocol; emit standalone property tests            |

When SwiftInferProperties detects a structure that maps to a no-protocol entry (Group, Ring), it still emits the inferred properties as standalone tests but skips the conformance suggestion. Adding such conformance suggestions back in is gated on parent-project coverage scope changes (`docs/SwiftProtocolLaws PRD.md` §4.3 Coverage Scope).

### 5.10 Milestones

> **Reconciled with §10 success criteria in v0.2.** v0.1 placed cross-function pairing at M6, but the §10 round-trip-on-3-packages criterion presumes pairing exists. Basic pairing now ships with M1.

| Milestone | Deliverable                                                                                                |
|-----------|------------------------------------------------------------------------------------------------------------|
| M1        | SwiftSyntax pipeline; CLI discovery tool; round-trip + idempotence templates; basic cross-function pairing (type + naming filter); rejection markers |
| M2        | Commutativity, associativity, identity element templates; project configuration (`.swiftinfer.toml`)        |
| M3        | Contradiction detection; cross-validation with TestLifter (§5.6)                                            |
| M4        | Scoring model surfaced in output (§5.3.1); sampling-before-suggesting (§5.5)                                |
| M5        | `@CheckProperty` and `@Discoverable` annotation API; `--dry-run` / `--stats-only` modes                     |
| M6        | Monotonicity (Possible by default; Likely+ via corroboration only); invariant-preservation (annotation-only); upstream-loop conformance suggestions (§5.9) |
| M7        | Semilattice template (subsumes Idempotence + Commutativity + Associativity when all three pass); Reducer / event-application template (Determinism property); expanded Identity Element detection (init-based + reduce-usage signals) |

-----

## 6. Contribution 2: TestLifter

### 6.1 Description

TestLifter analyzes existing XCTest and Swift Testing test suites, identifies structural patterns in test method bodies, and suggests generalized property tests derived from those patterns. The premise is that unit tests contain implicit structural knowledge that can be lifted into general properties with the developer's guidance.

### 6.2 Pattern Recognition

TestLifter parses test method bodies using SwiftSyntax and matches against a set of structural patterns:

#### Assert-after-Transform

```swift
// Detected pattern: value → transform → assert equality with original
func testRoundTrip() {
    let original = MyData(value: 42)
    let transformed = encode(original)
    let recovered = decode(transformed)
    XCTAssertEqual(original, recovered)
}
```

**Suggestion:** Round-trip property. The specific value `42` is incidental; the structure is general.

#### Assert-after-Double-Apply

```swift
// Detected pattern: value → f → f → assert equality with f(value)
func testNormalization() {
    let input = "  Hello  "
    let once = normalize(input)
    let twice = normalize(once)
    XCTAssertEqual(once, twice)
}
```

**Suggestion:** Idempotence property.

#### Assert-Symmetry

```swift
// Detected pattern: f(a, b) == f(b, a) for specific values
func testMergeOrder() {
    let a = Config(priority: 1)
    let b = Config(priority: 2)
    XCTAssertEqual(merge(a, b), merge(b, a))
}
```

**Suggestion:** Commutativity property.

#### Assert-Ordering-Preserved

```swift
// Detected pattern: a < b, then f(a) <= f(b)
func testDiscountPreservesOrder() {
    let low = Decimal(10)
    let high = Decimal(20)
    XCTAssertLessThanOrEqual(applyDiscount(low, 0.1), applyDiscount(high, 0.1))
}
```

**Suggestion:** Monotonicity property. (This is the primary corroboration path that lets monotonicity escape `Possible` — see §5.2 Monotonicity.)

#### Assert-Count-Change

```swift
// Detected pattern: count before, mutate, assert count after with arithmetic relationship
func testAppendIncreasesCount() {
    var stack = Stack<Int>()
    let before = stack.count
    stack.append(42)
    XCTAssertEqual(stack.count, before + 1)
}
```

**Suggestion:** Invariant preservation property — but only when `@CheckProperty(.invariantPreservation(...))` is also present on the target function (§5.2 Invariant Preservation).

### 6.3 Lifted Output Format

For each detected pattern, TestLifter emits a property test stub alongside provenance linking back to the originating unit test:

```swift
// LIFTED from: testRoundTrip() (MyDataTests.swift:14)
// Pattern: round-trip
// Confidence: Strong (score 0.88)
// Signals:
//   + Pattern matches across 3 distinct tests with structurally distinct inputs (+0.4)
//   + TemplateEngine corroborates roundTrip on (encode, decode)            (+0.4)
//   + Sampling: 25/25 passed                                                (+0.1)
// Original tests: testRoundTrip, testRoundTripEdgeCase, testRoundTripUnicode
// Original tests used specific inputs: MyData(value: 42), …(value: -1), …(value: "")
// This property generalizes to all MyData values.
//
// ⚠️  Requires a generator for MyData. Replace .todo below.

@Test func roundTripProperty() async {
    await propertyCheck(input: Gen.todo(MyData.self)) { value in
        #expect(decode(encode(value)) == value)
    }
}
```

#### How `.todo` blocks compilation

`Gen.todo(_:)` is declared with `@available(*, unavailable, message: "Replace .todo with a real generator")`. It compiles in source-form (so the surrounding stub is parseable, formattable, and reviewable in PRs) but produces an unavailable-symbol error at build time. This was chosen over alternatives:

| Option                          | Rejected because                                          |
|---------------------------------|-----------------------------------------------------------|
| `#error("...")`                 | Breaks file-level builds; can't even open the file        |
| Trailing `fatalError()` at runtime | Test runs and "passes" green until the assertion fires |
| Missing `Generator` conformance | Error message is opaque; doesn't link to documentation   |
| `@available unavailable`        | **Chosen.** Clear error, file still parses, links to docs |

The `.todo` mechanism is a deliberate forcing function — the stub does not compile until the developer provides a real generator, ensuring the lifted test is consciously adopted rather than blindly accepted.

### 6.4 Generator Inference

Where possible, TestLifter infers a generator from the types observed in the unit test. The strategy priority is **deterministic** and matches the parent project's §5.7 derivation order:

1. **CaseIterable enum:** `Gen.allCases`
2. **Memberwise-Arbitrary struct:** every stored property's type has a registered `Gen<T>` → compose them
3. **RawRepresentable enum (Int- or String-backed):** generate the raw and project
4. **Codable round-trip via test-extracted JSON literals:** if the test already contains JSON literals, derive a `Gen` that emits one of them at random
5. **Existing SwiftProtocolLaws registration:** if a `Gen<T>` was registered for ProtocolLawKit law checking, reuse it
6. **None of the above:** emit `Gen.todo(T.self)` (see §6.3)

The order is fixed because predictable generator choice is more important than picking the "best" one for any given type. A developer reviewing 30 lifted suggestions needs to know what `Gen.derived` means in their context without reading the inference internals each time.

### 6.5 Relationship to Existing Unit Tests

TestLifter does not modify or replace existing unit tests. The relationship is:

- **Unit tests** remain as regression anchors for specific known cases
- **Lifted properties** generalize those cases across the input space
- When a lifted property finds a new counterexample, it becomes a new unit test (a regression oracle)

This creates a feedback loop: unit tests seed property discovery; property tests generate new unit tests when they fail.

### 6.6 Confidence and Noise

Test-guided inference is inherently lower confidence than structural inference, because unit tests may encode accidental structure — patterns that happen to appear in the test values chosen, but don't represent real invariants.

TestLifter mitigates this through layered gates, applied in order:

1. **Minimum test count.** A pattern must appear in at least 2 distinct test methods before a suggestion is emitted (configurable via `.swiftinfer.toml`).
2. **Distinct-input requirement.** The input literals across those test methods must be **structurally distinct** — `42` and `42` count as one, `42` and `-1` count as two. Three tests using the same literal input do not satisfy this gate; they reveal a single test scenario duplicated, not a generalizable pattern.
3. **Flakiness gate.** A test is excluded from the lifting evidence pool if its body references any of:
   - `Date()`, `Date.now`, `CFAbsoluteTimeGetCurrent()`, or other time-of-day APIs
   - `URLSession`, `URLProtocol`, `Process`, file I/O at non-test-bundle paths
   - `random()`, `randomElement()`, `Bool.random()`, `SystemRandomNumberGenerator()`
   - Global state or `@MainActor` singletons accessed without setup/teardown
   
   Lifting a flaky test produces a flaky property and erodes trust fast. The flakiness detection is a syntactic heuristic, not a semantic analysis — a function named `currentDate()` that returns a fixed value still trips the gate. False positives here are acceptable (the test is excluded; another might still corroborate); false negatives are not.
4. **Cross-validation cap.** A TestLifter-only suggestion caps at `Likely` (§5.6). Strong confidence requires TemplateEngine corroboration.
5. **Suppression markers.** Developers annotate tests they want excluded:

   ```swift
   // swiftinfer: skip            (excludes this test from lifting evidence)
   func testRoundTrip() { ... }
   
   // swiftinfer: reject roundTrip (refuses this template on this test forever)
   func testRoundTrip() { ... }
   ```

### 6.7 Milestones

| Milestone | Deliverable                                                                          |
|-----------|--------------------------------------------------------------------------------------|
| M1        | SwiftSyntax test body parser (XCTest only); assert-after-transform detection; round-trip suggestion; `// swiftinfer: skip` |
| M2        | Double-apply (idempotence) and symmetry (commutativity) detection                     |
| M3        | Generator inference strategies (§6.4 ordered list); `.todo` stub mechanism (§6.3)     |
| M4        | Ordering and count-change pattern detection; flakiness gate                           |
| M5        | Distinct-input requirement; cross-validation merge with TemplateEngine; `// swiftinfer: reject` markers; Swift Testing body parsing |
| M6        | Feedback loop tooling — convert failing property counterexamples to unit test stubs    |

-----

## 7. Architecture Overview

```
┌──────────────────────────────────────────────────────┐
│                 SwiftInferProperties                 │
│                                                      │
│  ┌─────────────────┐      ┌───────────────────────┐  │
│  │  TemplateEngine │      │      TestLifter       │  │
│  │                 │      │                       │  │
│  │ SwiftSyntax     │      │ SwiftSyntax           │  │
│  │ signature scan  │      │ test body analysis    │  │
│  │                 │      │                       │  │
│  │ Template        │      │ Pattern registry      │  │
│  │ registry        │      │ (structural lifting)  │  │
│  │                 │      │                       │  │
│  │ Sampling §5.5   │      │ Flakiness gate §6.6   │  │
│  │ Scoring §5.3.1  │      │ Generator inference   │  │
│  │ @CheckProperty  │      │ Provenance tracking   │  │
│  │ @Discoverable   │      │                       │  │
│  └────────┬────────┘      └───────────┬───────────┘  │
│           │                           │              │
│           └──────────┬────────────────┘              │
│                Cross-validation merge §5.6           │
│                      │                               │
│                Project config §5.8                   │
│                      │ emits stubs using             │
└──────────────────────┼───────────────────────────────┘
                       │
┌──────────────────────▼───────────────────────────────┐
│                 SwiftProtocolLaws                    │
│            PropertyBackend abstraction               │
│       swift-property-based (single v1 backend)       │
└──────────────────────────────────────────────────────┘
```

### 7.1 Cross-Module Strategy

SwiftSyntax operates per-file. Property inference often spans modules (e.g., `encode` defined in `ModuleA`, `decode` in `ModuleB`). v1 takes the conservative path:

- **v1 default:** single-target analysis. The Discovery CLI scans one target at a time. Cross-target round-trip pairs are not detected.
- **v1 escape hatch:** explicit cross-target analysis via `--targets ModuleA,ModuleB`, which loads multiple targets into a unified scan. Naive `Source` parsing only — no SymbolGraph integration in v1.
- **v1.1 candidate:** SymbolGraph-based cross-module indexing. The Swift compiler emits `*.symbols.json` per build target; loading those alongside SwiftSyntax provides cross-module type and function resolution. Out of scope for v1 because the indexing pipeline is non-trivial and the single-target case covers the majority of real-world inference.

Documenting the limitation up front avoids the worse failure mode where developers expect cross-module inference, don't get it, and conclude SwiftInferProperties is broken.

### 7.2 Incremental Analysis

A full re-scan of every file on every build is acceptable for the Discovery CLI (run on demand, not in the inner loop). A compiler-plugin mode (Open Question 2) requires incremental analysis: re-scan only changed files, cache the rest.

v1 ships the CLI with no caching. v1.1 introduces a cache keyed on `(file SHA, template registry version, project config hash)`. A cache invalidation on registry-version bumps is required; a stale cache emitting suggestions that no longer match the current registry would be worse than no cache.

-----

## 8. Relationship to SwiftProtocolLaws

SwiftInferProperties is explicitly downstream of SwiftProtocolLaws and does not duplicate its concerns:

| Concern                                       | Handled By                          |
|-----------------------------------------------|-------------------------------------|
| Protocol semantic law verification            | SwiftProtocolLaws (ProtocolLawKit)  |
| Protocol conformance detection                | SwiftProtocolLaws (ProtoLawMacro)   |
| Missing protocol suggestions                  | SwiftProtocolLaws (ProtoLawMacro)   |
| Structural property inference from signatures | SwiftInferProperties (TemplateEngine) |
| Property inference from unit tests            | SwiftInferProperties (TestLifter)    |
| Test execution backend                        | SwiftProtocolLaws (PropertyBackend) — shared |
| Generator registry (actor-isolated)           | SwiftProtocolLaws — shared           |

### Shared generator registry

ProtocolLawKit's generator registry (parent project §4.5, actor-isolated) is the single source of truth. SwiftInferProperties registers its inferred generators into the same actor and looks up existing registrations from there. There is no separate SwiftInferProperties-side cache.

### Conflict resolution when both tools target the same function

If ProtoLawMacro detects `MyType: Equatable` and emits `checkEquatableProtocolLaws(MyType.self)`, and SwiftInferProperties separately infers `f(f(x)) == f(x)` on a method of `MyType`, both suggestions ship — they cover different properties on the same type. No deduplication is attempted.

If SwiftInferProperties infers a property that exactly matches an existing ProtocolLawKit law for a protocol `MyType` already conforms to, the SwiftInferProperties suggestion is **suppressed** with a comment noting that ProtocolLawKit already covers it. This prevents double-coverage clutter.

If SwiftInferProperties infers a Monoid-shaped pattern on a type that does *not* conform to `AdditiveArithmetic`, §5.9's upstream-loop suggestion fires.

-----

## 9. Risks and Mitigations

| Risk                                                | Likelihood | Mitigation                                                                       |
|-----------------------------------------------------|------------|----------------------------------------------------------------------------------|
| Template matching produces too many false positives | High       | Conservative confidence tiers; sampling-before-suggesting (§5.5); type-pattern-first (§5.2) |
| Lifted unit test patterns don't generalize          | Medium     | Distinct-input requirement; flakiness gate; cross-validation cap at Likely (§6.6) |
| Generator inference fails for complex types         | Medium     | Deterministic fallback to `.todo` stub; never silently skip                       |
| Cross-function pairing is noisy without grouping    | Medium     | Type filter eliminates most pairs; `@Discoverable` groups available               |
| Property contradictions cause user confusion        | Low        | Curated contradiction table (§5.4); explanatory warnings on cross-validation conflicts |
| Developers ignore generated stubs                   | Medium     | Compile-time enforcement via `.todo`; rejection markers persist across runs       |
| **Suggestion fatigue (new in v0.2)**                | **High**   | Hard per-module cap (default 10); precision-over-recall philosophy (§1.3); rejection markers prevent re-emission |
| **Stale `.swiftinfer.toml` (new in v0.2)**          | **Low**    | Config schema versioning; warn on unknown keys; never silently ignore             |
| **SymbolGraph misalignment if cross-module ships**  | **Medium** | Out of scope for v1; explicit `--targets` flag is the v1 escape hatch (§7.1)      |

-----

## 10. Success Criteria

### Calibration: precision targets per tier

The §4 precision targets are the validation anchors. v1 ships when benchmark runs hit:

- **Strong suggestions:** ≥ 90% accepted by reviewing developers
- **Likely suggestions:** ≥ 70% accepted
- **Possible suggestions:** no target (opt-in tier)

"Accepted" means the developer adopts the suggestion as a real test (possibly with edits) rather than rejecting it via `// swiftinfer: reject` or deletion.

### TemplateEngine

- Running the discovery CLI on a real-world Swift module of 50+ functions produces **at most 10 Strong-confidence suggestions** (hard cap, §5.8), of which **at least 90% are accepted** (Strong precision target).
- Round-trip, idempotence, and commutativity templates correctly identify known patterns in **at least 3 open-source Swift packages** used as benchmarks. (M1 ships basic cross-function pairing, so this criterion is reachable from M1+M2.)
- Contradiction detection (§5.4) correctly fires on idempotent + involutive and at least 2 other known contradictory combinations.
- Scoring breakdown (§5.3.1) is present in 100% of emitted suggestions.

### TestLifter

- Running on a test suite of 50+ XCTest methods correctly identifies **at least 5 liftable patterns** with Strong or Likely confidence.
- At least **90% of emitted stubs compile** after the developer resolves `.todo` generators.
- **No existing unit test is modified or deleted** by the tool under any circumstances.
- Flakiness gate excludes time-, network-, random-, and global-state-using tests with **zero false negatives** in the benchmark suite.

### Cross-validation

- For at least 3 properties present in benchmark packages, TemplateEngine and TestLifter independently arrive at the same suggestion (corroboration path exercised, not just specified).

### False-positive rate

- Across all benchmark suites, at most **5% of Strong suggestions are rejected** by reviewing developers in the first review pass.

-----

## 11. Open Questions

1. **Separate package or monorepo?** Should SwiftInferProperties be a separate package from SwiftProtocolLaws, or a set of additional targets in the same repository? Separate packages preserve independent versioning; a monorepo simplifies shared abstractions and the generator-registry hand-off.
2. **TemplateEngine as compiler plugin vs. CLI?** The discovery CLI is the right model for whole-module scanning, but should TemplateEngine also expose a compiler plugin mode for incremental per-file suggestions during development? Incremental analysis (§7.2) is a prerequisite.
3. **TestLifter and Swift Testing vs. XCTest?** Swift Testing's `@Test` macro makes test body parsing harder than XCTest's method-based structure. M1 targets XCTest only; Swift Testing parsing lands in M5.
4. **Community template contributions:** The template registry is the most valuable long-term artifact. Should it be designed as an extensible registry that third parties can contribute to, or kept curated and closed for quality control? Project-level synonyms (§5.8) provide a partial answer; full custom-template authoring is a different question.
5. **Integration with SwiftProtocolLaws ProtoLawMacro:** §5.9 codifies the upstream-loop conformance suggestion. Should TemplateEngine's structural analysis feed *additional* signals into ProtoLawMacro's missing-conformance suggestions (e.g., "this type pattern matches Monoid — ProtoLawMacro should suggest `AdditiveArithmetic`"), or remain strictly separate?
6. **Rejection persistence (new in v0.2):** Should `// swiftinfer: reject <template>` markers live in source files (current proposal — survives refactors, visible in PRs) or in a separate `.swiftinfer-rejections` file (current proposal — separates noise from production code)? In-source has the advantage of tying the rejection to the relevant declaration; sidecar file has the advantage of not cluttering production code with tooling artifacts.
7. **Stateful inference carve-out (new in v0.2):** Full model-based testing is firmly out of scope. But narrow stateful inference — `push`/`pop` affecting `count`, `insert` increasing `Set.count` by 0 or 1 — is plausibly tractable as a v1.1 template. Should v1 leave architectural room for this (e.g., abstracting the "before/after measurement" pattern in invariant-preservation), or wait until v1.1 has concrete proposals?
8. **Precondition harvesting (new in v0.2):** Every `guard`, `precondition`, and `assert` is an explicit invariant statement by the author. Harvesting them as testable properties is genuinely novel territory — closer to Daikon (a non-goal, §3) but driven by static analysis rather than dynamic instrumentation. The risk is that most `guard`s express input-validation, not behavioral invariants, so the noise floor is high. v1.1 candidate, gated on whether benchmark codebases yield enough useful predicates to justify the template.
9. **Comment-derived signals (new in v0.2):** "Should never happen" comments, doc-comment phrasing like "must always be sorted" or "this is the neutral value", and similar prose are gold mines if extractable but a noise factory if not. v1.1 candidate, gated on prototyping with a small fixed phrase-list against benchmark repos. v1 ignores comments entirely.
10. **Determinism as a general-purpose template (new in v0.2):** The Reducer template's v1 property is determinism. Should determinism become a separate general-purpose template that fires on any pure-shaped function, or stay scoped to the reducer pattern? Argument for general-purpose: catches hidden state in non-reducer pure functions. Argument against: every getter would be a candidate, exploding the noise budget. Currently scoped to reducers only; revisit after v1 benchmark data.

-----

## 12. References

- [SwiftProtocolLaws PRD](../SwiftProtocolLaws%20PRD.md) — upstream dependency, v0.3 current
- [swift-property-based](https://github.com/x-sheep/swift-property-based) — execution backend (single backend per parent project §4.8)
- [SwiftSyntax](https://github.com/apple/swift-syntax) — static analysis foundation
- [EvoSuite](https://www.evosuite.org) — Java property inference inspiration
- [Daikon](https://plse.cs.washington.edu/daikon/) — runtime invariant inference reference (out of scope here, listed for context)
- [QuickSpec](https://hackage.haskell.org/package/quickspec) — Haskell equational property discovery
- [Hedgehog state machines](https://hedgehog.qa) — stateful testing reference (out of scope, noted for §11 Question 7)

-----

## Appendix A: Changelog from v0.1

v0.2 incorporates feedback from three external reviewers (`docs/Property Inference/ChatGPT critique of PRD.md`, `Copilot critique of PRD.md`, `Gemini critique of PRD.md`) and aligns the document with the parent project's v0.3 single-backend-by-design decision.

### Substantive changes

1. **§1.3 added: "High Precision, Low Recall" philosophy.** The dominant failure mode for inference tooling is suggestion noise; v0.2 makes the tradeoff explicit so later design choices have a north star.
2. **§2.4 added: Semantic ambiguity in inference.** Surfaces up front that names lie and structural shapes mislead — the same risk three reviewers independently flagged.
3. **§3 Goals: explainability added; rejection-persistence added.** Explainability becomes a first-class goal; rejections survive across runs.
4. **§4 Confidence Model: precision targets per tier (≥90% / ≥70% / unbounded).** Confidence is now *computed* from §5.3.1 scoring rather than assigned by template authors. Counterexamples filter rather than annotate.
5. **§5.2 restructured: type pattern necessary, name signals escalator-only.** Names alone never produce a candidate or reach Strong. Mirrors Gemini's primary recommendation.
6. **§5.2 Monotonicity demoted.** Possible by default; Likely+ requires TestLifter corroboration or explicit `@CheckProperty(.monotonic(.increasing/.decreasing))` annotation. Direction is part of the annotation, not a runtime guess. Moved from M4 to M6 so corroboration infrastructure exists when it ships.
7. **§5.2 Invariant Preservation: annotation-required.** Removed from automatic suggestion entirely; only fires with `@CheckProperty(.invariantPreservation(...))`.
8. **§5.2 Commutativity: anti-signal names added.** `subtract`, `difference`, `apply`, `prepend`, `append` cap suggestions at Possible.
9. **§5.3.1 added: scoring model.** Additive signals with documented weights, surfaced in every emitted suggestion. Mirrors ChatGPT's transparency recommendation.
10. **§5.3 expanded: overloaded function pairing.** Pair key is `(input-type, output-type)`, preventing combinatorial explosion on `encode`/`decode` overloads.
11. **§5.5 added: sampling-before-suggesting is mandatory** for Likely+. Counterexamples filter rather than warn.
12. **§5.6 added: cross-validation between TemplateEngine and TestLifter.** Independent corroboration boosts; single-source caps at Likely; conflicts demote to Possible with explanatory warning.
13. **§5.7 expanded: annotations work on extensions.** `@CheckProperty` and `@Discoverable` valid on extension declarations and extension members.
14. **§5.7 added: rejection markers.** `// swiftinfer: reject <template>` persists across runs, per-template granularity.
15. **§5.8 added: project configuration.** `.swiftinfer.toml` for per-project naming synonyms, template enable/disable, per-module suggestion cap.
16. **§5.9 added: reinforcing the upstream loop.** Inferred properties matching ProtocolLawKit law catalogs suggest *conformance*, not one-off tests.
17. **§5.10 milestones reconciled.** Basic cross-function pairing moved into M1 (was M6) so the §10 round-trip-on-3-packages criterion is reachable from M1+M2. Monotonicity moved to M6 (was M4).
18. **§6.3 expanded: `.todo` blocking mechanism specified.** `@available(*, unavailable, message: ...)` chosen over `#error`, runtime `fatalError`, or missing-conformance approaches; rationale documented.
19. **§6.4 specified: deterministic generator-inference priority.** Six-step ordered list, matching parent project §5.7.
20. **§6.6 tightened.** Distinct-input requirement (literal-equality across tests disqualifies); flakiness gate (`Date()`, `URLSession`, `random()`, global state); cross-validation cap; rejection markers.
21. **§6.7 milestones updated.** Flakiness gate at M4; distinct-input + cross-validation merge + rejection markers + Swift Testing parsing at M5.
22. **§7.1 added: cross-module strategy.** Single-target by default in v1; explicit `--targets` opt-in; SymbolGraph-based indexing deferred to v1.1.
23. **§7.2 added: incremental analysis policy.** Full rescan in v1; cache in v1.1, keyed on registry version among other things.
24. **§8 expanded: shared generator registry; conflict resolution rules.** Clarifies what happens when both ProtoLawMacro and SwiftInferProperties target the same type/function.
25. **§9 added: suggestion fatigue, stale config, SymbolGraph-misalignment risks** with mitigations.
26. **§10 expanded: numeric precision targets per tier; cross-validation criterion; false-positive-rate criterion.**
27. **§11 added Open Questions 6 (rejection persistence location) and 7 (stateful inference carve-out for v1.1).**
28. **§12 References: SwiftQC removed.** Per parent project v0.3 single-backend-by-design decision; the v0.1 reference to SwiftQC as "alternative backend" was stale.

### Substantive changes (round 2 — algebraic-structure inference, drawn from follow-up Gemini consultations)

29. **§2.3.1 added: novelty positioning.** Documents the absence of comparable inference layers in other languages (QuickCheck/EvoSuite/Daikon/refinement types) and Swift's structural advantages, while keeping the framing as positioning context rather than a marketing claim.
30. **§5.2 Identity Element expanded with three detection rules.** v0.1 detected only static-named constants; v0.2 round 2 adds parameter-less initializers (`String()`, `Set<Element>()`, `Config()`) validated via sampling, and `reduce(_:_:)` seed-usage as a third strong signal. Comment-derived detection deferred to Open Question 9.
31. **§5.2 Semilattice template added.** Catches configuration-merge / "take-the-max" / feature-flag composition patterns as a single algebraic-structure candidate rather than three independent suggestions on the same function. Includes a subsumption rule that suppresses the standalone Idempotence + Commutativity + Associativity suggestions when the semilattice fires. Identity-bearing semilattices (bounded semilattices) are flagged for the §5.9 `SetAlgebra` mapping.
32. **§5.2 Reducer / Event Application template added.** Catches state-machine, event-sourcing, SwiftUI/TCA-reducer, and analytics-aggregation shapes. v1 property is Determinism (call `reduce(s, e)` twice, assert equal); richer reducer-specific properties (commutativity of independent events, idempotence of normalize-events) require user annotation and ship in v1.1.
33. **§5.9 mapping table added.** Replaces the prose-only Monoid example with a curated mapping of inferred algebraic structures to ProtocolLawKit conformance suggestions: Monoid → `AdditiveArithmetic`, Bounded Semilattice → `SetAlgebra`, Total Order → `Comparable`, Round-trip → `Codable`. Group / Ring entries note the absence of standard-library protocols and emit standalone tests instead.
34. **§5.10 M7 added.** Algebraic-structure templates (Semilattice, Reducer) and the expanded Identity Element detection rules ship in M7. M6 retains Monotonicity, Invariant Preservation, and the upstream-loop suggestions.
35. **§11 Open Questions 8, 9, 10 added.** Precondition harvesting (`guard`/`precondition`/`assert` as static invariants); comment-derived signals ("should never happen" / "neutral element" prose); Determinism as a general-purpose template versus reducer-scoped. All three are v1.1 candidates gated on v1 benchmark data.
36. **§5.6.1 Existing-Test Detection added.** TemplateEngine indexes existing `propertyCheck`/`forAll` calls in test targets and suppresses suggestions for properties already covered by hand-written or previously-adopted tests. Three coverage categories: hand-written (silent suppression), previously-generated-and-adopted (silent), unit tests covering a single case (suggestion still emitted with a generalization note). Closes the gap of re-suggesting properties that the project already tests.

### Items considered in round 2 and not adopted

- **Pipeline composition associativity** as its own template. Composition of `pass3 ∘ pass2 ∘ pass1` is associative by construction in Swift — there is no testable property here that isn't trivially type-system-enforced. The interesting properties (each pass is idempotent, each pass preserves an invariant) are already covered by the Idempotence and Invariant Preservation templates.
- **Group inference (`apply` / `undo` / `inverse`)** as a template. Genuine groups are rare in Swift codebases outside of specific domains (text-editor undo stacks, CRDTs), and the existing Round-Trip template already catches the most common group-shaped patterns (`apply`/`undo` inverse pairs). Promoting Group to its own template adds maintenance cost without obvious benefit. Listed in §5.9's mapping table as "no standard library protocol; emit standalone property tests" so the inference is still possible when annotated.
- **Ring inference** (additive + multiplicative + distributivity). Numeric pipelines do form rings, but the relevant properties are already covered by `AdditiveArithmetic` law checking in ProtocolLawKit. Ring inference would duplicate that coverage.
- **Behavioral inference (Daikon-style runtime invariant detection).** Out of scope per §3 Non-Goals. Static-only inference is the v1 commitment; dynamic instrumentation is a separate project.
- **A "four pillars" architectural framing** (structural / behavioral / algebraic / semantic inference). Conceptually clarifying but aspirational; v1 ships structural + algebraic only, and erecting a four-pillar architecture in the PRD would imply scope commitments to behavioral and semantic inference that aren't justified by current scoping.

### Editorial changes

- Architecture diagram updated to reflect §5.5 sampling, §5.6 cross-validation, §6.6 flakiness gate.
- "Likely" softened to "plausibly" in §2.1 examples to set expectations correctly.
- Reference link to parent PRD updated to relative path matching repo layout.

### Items raised by reviewers and not adopted in v0.2

- **ChatGPT: ComparisonStrategy<T> abstraction over `==` for floating-point and approximate equality.** Acknowledged as a real gap for floating-point types. Deferred to v1.1 because the §5.2 templates for v1 (round-trip, idempotence, commutativity, associativity, identity-element) are dominated by exact-equality use cases in practice; introducing a comparison-strategy parameter on every emitted stub would cost more in API surface than it pays in reduced false positives during v1. Re-evaluate against v1 benchmark data.
- **ChatGPT: contradiction-detection evolution into a property algebra / implication graph.** §5.4 stays curated. The parent project explicitly chose curated pattern-warnings over graph reasoning (§5.6 of the parent PRD); SwiftInferProperties follows that precedent. Soundness/completeness over a property algebra is not aspired to.
- **Gemini: full stateful inference.** Out of scope for v1 (§3 Non-Goals). A narrow `push`/`pop` style carve-out is preserved as Open Question 7 for v1.1.
- **Copilot: developer-satisfaction success criterion.** Acceptance rate (§10) is a measurable proxy; "satisfaction" without an instrument is not actionable.

-----

## Appendix B: v0.1 Document

The v0.1 document is preserved at `docs/Property Inference/SwiftInferProperties PRD v0.1.md` for historical reference.
