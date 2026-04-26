# Product Requirements Document

## SwiftProtocolLaws: Protocol Law Testing for Swift

**Version:** 0.3 Draft
**Status:** Proposal
**Audience:** Open Source Contributors, Swift Ecosystem
**Supersedes:** v0.2 (in-place evolution; Appendix A is the v0.2 → v0.3 changelog) and v0.1 (preserved alongside as `SwiftProtocolLaws PRD v0.1.md`; Appendix B is the v0.1 → v0.2 changelog).

-----

## 1. Overview

Swift's protocol system creates a gap between structural conformance — which the compiler verifies — and semantic conformance, which it cannot. A type may declare `Equatable` while implementing `==` incorrectly. A `Comparable` implementation may violate transitivity. A `Codable` round-trip may silently lose data. None of these violations are detectable at compile time.

**SwiftProtocolLaws prevents subtle semantic bugs that escape code review and static analysis, without requiring developers to write or maintain property-based test infrastructure per type.**

This document proposes **SwiftProtocolLaws**, an open source Swift package delivering two separable but complementary contributions:

- **Contribution 1 — ProtocolLawKit**: A curated library of protocol law property tests, generic over any conforming type, usable standalone with any property-based testing backend.
- **Contribution 2 — ProtoLawMacro**: A Swift tooling layer (a per-suite macro/trait plus a build-tool plugin) that detects protocol conformances in a codebase and generates ProtocolLawKit test registrations, eliminating manual test wiring.

These two contributions are intentionally decoupled. ProtocolLawKit ships first and has independent value. ProtoLawMacro depends on ProtocolLawKit and adds automation.

### 1.1 Why Now

Several recent shifts in the Swift ecosystem make this proposal feasible *and* timely:

- Swift macros (SE-0382 et al.) are stable enough to support compile-time generation reliably.
- Swift Testing supersedes XCTest as the official testing system, with a trait system that this proposal can integrate with rather than work around.
- `swift-property-based` and SwiftQC are both active enough to serve as backends without bootstrapping our own generator/shrinking infrastructure.
- The protocol surface itself has expanded (`Sendable`, `Identifiable`, `AdditiveArithmetic`, `Actor`) — more conformance contracts in flight, more value in checking them.
- Apple's broader correctness push (SwiftData, structured concurrency, ownership) signals an audience already attuned to "the compiler can't catch everything we care about."

-----

## 2. Problem Statement

### 2.1 The Structural/Semantic Gap

Swift's compiler enforces the *structural* contract of a protocol — the required methods and properties exist with correct signatures. It does not and cannot enforce the *semantic* contract — the behavioral protocol laws that a correct implementation is expected to satisfy.

Examples of semantic violations that compile without error:

```swift
// Violates symmetry: x == y may differ from y == x
extension MyType: Equatable {
    static func ==(lhs: MyType, rhs: MyType) -> Bool {
        return lhs.priority > rhs.priority
    }
}

// Violates hash/equality consistency
extension MyType: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(UUID()) // always unique, breaks Dictionary
    }
}

// Violates round-trip fidelity
extension MyType: Codable {
    // encode omits a field; decode provides a default
    // decode(encode(x)) != x for non-default values
}
```

Each of these is a real class of production bug. None is caught by the type system.

### 2.2 The Activation Energy Problem

Developers who understand property-based testing could write these protocol law checks themselves. Most do not, because:

- Translating prose specifications (the `Equatable` documentation) into property tests requires deliberate effort per type.
- No standard library of protocol law checks exists for Swift.
- The connection between protocol conformance and testable properties is implicit, not surfaced by tooling.

### 2.3 The Ecosystem Gap

Adjacent ecosystems already solve this:

- **Rust** has `proptest` plus the `arbitrary` derive macro: type-directed generator synthesis bundled with a property runner.
- **Haskell** has QuickCheck plus community law libraries (`quickcheck-classes`, `checkers`) that ship the algebraic-law checks for `Eq`, `Ord`, `Functor`, `Monoid`, etc.

Swift has neither piece. The Swift property-based testing ecosystem has two active packages (`swift-property-based`, SwiftQC) providing generation and shrinking infrastructure, but no protocol law library and no static-analysis layer connecting conformance declarations to property test generation. This gap is unoccupied.

-----

## 3. Goals and Non-Goals

### Goals

- Provide a complete, accurate library of semantic protocol law checks for Swift's core protocols, with each protocol law explicitly classified by strictness (see §4.2).
- Make protocol law checking available to any Swift project with a one-line addition per type, while honestly surfacing what *one line + a generator + interpretation* actually requires.
- Integrate naturally with `swift-property-based` as the default backend.
- Keep the backend swappable by design, while deferring the public abstraction surface until a second backend is actually wired up (see §4.5).
- Provide tooling (per-suite macro/trait + build-tool plugin) that eliminates manual protocol law registration through static analysis.
- Surface missing protocol conformances as opt-in suggestions, not just verify existing ones.
- Produce human-reviewable output, not silent automatic test generation.

### Non-Goals

- Replacing unit tests or general property-based testing.
- Supporting stateful / model-based testing (separate project scope).
- Formal verification.
- Full EvoSuite parity (domain-specific property inference is out of scope for v1).
- Automatic code fixing of detected protocol law violations.
- Treating every protocol law as equally absolute — see strictness tiers, §4.2.

-----

## 4. Contribution 1: ProtocolLawKit

### 4.1 Description

ProtocolLawKit is a standalone Swift package providing a typed registry of protocol law property tests. Each protocol law is expressed as a generic function parameterized over a conforming type, runnable against any property-based testing backend through a thin abstraction protocol.

### 4.2 Protocol Law Strictness Tiers

Not every "law" associated with a Swift protocol is universally true in idiomatic Swift code. `Hashable` explicitly allows hash collisions; `Codable` round-trips are intentionally lossy for many real schemas; `Comparable` on floating-point intentionally fails for `NaN`. Presenting all such laws as absolute would generate false positives and erode trust.

Every check ProtocolLawKit ships carries one of three explicit strictness tiers:

| Tier | Meaning | Default behavior on violation | Examples |
|---|---|---|---|
| **Strict** | Must hold for any correct conformance. A violation is a bug. | Test failure. | `Equatable` reflexivity, symmetry, transitivity; `Comparable` antisymmetry; `SetAlgebra` empty identity. |
| **Conventional** | Usually expected, but situationally violated by design. Caller can opt in to strict enforcement. | Warning by default; failure when `.strict` is requested. | `Codable` exact round-trip equality; `Comparable` totality on `Float`/`Double`; `Collection` non-mutation on lazy views. |
| **Heuristic** | A useful signal, not a correctness claim. Best for detecting accidental violations. | Informational only — never fails the test. | `hashValue` distribution sanity; iterator non-reuse hints. |

The tier appears in:

- The §4.3 tables (a `Tier` column per protocol).
- The output of every check (`CheckResult.tier`).
- The default failure policy — `Conventional` and `Heuristic` violations do *not* fail CI unless the caller opts in via `.strict`.

This addresses the recurring critique that some advertised laws (lossy `Codable`, `NaN`, lazy collections) are intentionally violated in correct Swift code.

### 4.3 Supported Protocol Laws

**Inheritance semantics.** When a protocol extends another (e.g. `Hashable` extends `Equatable`, `Comparable` extends `Equatable`, `Collection` extends `Sequence`), each check function runs the **inherited laws by default**. Calling `checkHashableProtocolLaws` runs Equatable's laws *and* Hashable's:

```swift
// One call. Runs Equatable.{reflexivity, symmetry, transitivity, negationConsistency}
// AND Hashable.{equalityConsistency, stabilityWithinProcess, distribution}.
try await checkHashableProtocolLaws(for: MyType.self, using: Gen.myType())
```

This is the safe default. Property tests are expensive enough that "remember to chain inherited suites" cannot be a per-call developer responsibility — forgetting is a silent way to miss exactly the kind of semantic bugs this library exists to catch. Each inherited check produces its own `CheckResult` (`Equatable.symmetry`, `Hashable.equalityConsistency`, etc.) so test runner output stays attributable and a single suite's failure points at the actual offending law, not its descendant.

**Opt-out: `.ownOnly`.** Pass `laws: .ownOnly` to run only the protocol's own table — useful when the inherited suite has already run separately, when iterating on a single law, or when budget is tight and you've audited the inherited conformance:

```swift
// Skip Equatable's suite this run; we ran it explicitly above with a richer generator.
try await checkHashableProtocolLaws(
    for: MyType.self,
    using: Gen.myType(),
    laws: .ownOnly
)
```

**Plugin emits one call per type, the most specific one.** For a `Hashable` type, the Discovery plugin (§5.3) emits `checkHashable` and *not* a separate `checkEquatable`, since `checkHashable` already runs Equatable's suite by default. For a `Comparable & Codable` type it emits `checkComparable` (covers Equatable) plus `checkCodable`. This avoids the duplicate-runs-of-inherited-laws cost that the explicit-composition design would create when both calls appear in the same suite.

#### `Equatable`

| Protocol Law | Tier | Description |
|---|---|---|
| Reflexivity | Strict | `x == x` for all `x` |
| Symmetry | Strict | `x == y` implies `y == x` |
| Transitivity | Strict | `x == y` and `y == z` implies `x == z` |
| Negation consistency | Strict | `x != y` iff `!(x == y)` |

Floating-point `NaN` is the canonical intentional violation; types containing `Float`/`Double` should pass `.allowNaN` to opt out of reflexivity over `NaN`.

#### `Hashable` (extends `Equatable` protocol laws)

| Protocol Law | Tier | Description |
|---|---|---|
| Hash/equality consistency | Strict | `x == y` implies `x.hashValue == y.hashValue` |
| Hash stability within a process | Conventional | `x.hashValue` constant across calls in one program run |
| Hash distribution | Heuristic | Hashes don't collapse to a small set across the generator |

`hashValue` is explicitly *not* required to be stable across runs (Swift randomizes hashing per launch); ProtocolLawKit does not check cross-run stability.

#### `Comparable` (extends `Equatable` protocol laws)

| Protocol Law | Tier | Description |
|---|---|---|
| Antisymmetry | Strict | `x <= y` and `y <= x` implies `x == y` |
| Transitivity | Strict | `x <= y` and `y <= z` implies `x <= z` |
| Totality | Conventional | `x <= y` or `y <= x` for all `x`, `y` (relaxed for `Float`/`Double` because of `NaN`) |
| Operator consistency | Strict | `>`, `>=`, `<` are consistent with `<=` |

#### `Codable`

| Protocol Law | Tier | Description |
|---|---|---|
| Round-trip fidelity | Conventional | `decode(encode(x)) == x` for all `x` (default mode: exact equality) |
| Encoder independence | Conventional | Round-trip holds for all standard encoder/decoder pairs |

`Codable` round-trip ships with three modes to accommodate real-world lossy encodings:

- `.strict` — exact equality required.
- `.semantic(equivalent:)` — caller-provided equivalence predicate, for cases where representational round-trip is intentionally lossy (canonicalized dates, normalized whitespace, etc.).
- `.partial(fields:)` — round-trip preserves a named subset of fields, for versioned schemas with default-bearing additions. Fields are typed `[PartialKeyPath<T>]`, not strings, so they survive renames and refactors:
  ```swift
  mode: .partial(fields: [\Invoice.id, \Invoice.amount])
  ```

#### `IteratorProtocol`

| Protocol Law | Tier | Description |
|---|---|---|
| Termination stability | Conventional | Once `next()` returns `nil`, subsequent calls also return `nil` (the iterator stays exhausted) |
| Single-pass yield | Conventional | An iterator yields each element at most once across a complete iteration |

#### `Sequence`

| Protocol Law | Tier | Description |
|---|---|---|
| `underestimatedCount` lower bound | Strict | The iterator yields at least `underestimatedCount` elements |
| Multi-pass consistency | Conventional | For non-single-pass sequences, two fresh iterators yield the same elements in the same order |
| `makeIterator()` independence | Conventional | Calling `makeIterator()` does not perturb prior iterators or the sequence's observable state |

`Sequence` does not require multi-pass iteration in general; sequences that document themselves as single-pass (e.g. `AnyIterator` wrappers, network streams) pass `.singlePass` to suppress the multi-pass and `makeIterator()`-independence checks.

#### `Collection`

| Protocol Law | Tier | Description |
|---|---|---|
| Count consistency | Strict | `count` matches number of iterated elements |
| Index validity | Strict | All indices between `startIndex` and `endIndex` are valid |
| Non-mutation | Conventional | Iteration does not modify the collection (relaxed for lazy / view-like wrappers) |

`checkCollectionProtocolLaws` runs the `Sequence` and `IteratorProtocol` suites first per the §4.3 inheritance convention.

#### `SetAlgebra`

| Protocol Law | Tier | Description |
|---|---|---|
| Union idempotence | Strict | `x.union(x) == x` |
| Intersection idempotence | Strict | `x.intersection(x) == x` |
| Union commutativity | Strict | `x.union(y) == y.union(x)` |
| Intersection commutativity | Strict | `x.intersection(y) == y.intersection(x)` |
| Empty identity | Strict | `x.union(.empty) == x` |
| Symmetric-difference self-empty | Strict | `x.symmetricDifference(x) == .empty` |
| Symmetric-difference empty identity | Strict | `x.symmetricDifference(.empty) == x` |
| Symmetric-difference commutativity | Strict | `x.symmetricDifference(y) == y.symmetricDifference(x)` |
| Symmetric-difference definition | Strict | `x.symmetricDifference(y) == x.union(y).subtracting(x.intersection(y))` |

The four `symmetricDifference*` laws were added in response to a real-world miss: pre-fix `swift-collections@35349601`, `TreeSet.symmetricDifference` returned the *intersection* via a `_Bitmap` typo (`&` instead of `^`). The original five-law SetAlgebra suite — union/intersection idempotence + commutativity + emptyIdentity — does not exercise `symmetricDifference` at all and would not have caught the bug. The retroactive validation in `Validation/Pass3` pins the kit against the pre-fix SHA and asserts the new laws fire.

#### Coverage Scope

ProtocolLawKit v1 covers the protocols enumerated above. The Swift Standard Library has roughly 54 public protocols (see `docs/Swift Standard Library Protocols.md` for the full inventory); v1's coverage is deliberate and audited rather than exhaustive. Other stdlib protocols are categorized as follows:

**v1.1 candidates (testable laws, clear contracts):**

- `BidirectionalCollection`, `RandomAccessCollection`, `MutableCollection`, `RangeReplaceableCollection` — refinements of `Collection`; their laws layer on top of v1's `Collection` laws (`index(before:)` inverts `index(after:)`, replace/insert/remove round-trips, etc.).
- `AdditiveArithmetic`, `Numeric`, `SignedNumeric` — algebraic laws (associativity, commutativity, identity, additive inverse).
- `BinaryInteger`, `SignedInteger`, `UnsignedInteger`, `FixedWidthInteger` — integer arithmetic and bitwise operator consistency, overflow-trap vs `&`-overflow contracts.
- `FloatingPoint`, `BinaryFloatingPoint` — IEEE-754 contracts excluding `NaN`-domain edges (which are `.allowNaN`-gated).
- `Strideable` — `advanced(by:).distance(to: original) == -n` round-trip.
- `RawRepresentable` — `T(rawValue: x.rawValue) == x` round-trip for synthesized cases.
- `LosslessStringConvertible` — `T(String(describing: x)) == x` round-trip.
- `StringProtocol` — extends `BidirectionalCollection` with text-specific laws (Unicode-correctness invariants).
- `Identifiable` — `id` stability across calls within a process (Conventional, since cross-process stability is contextual).
- `CaseIterable` — `allCases` enumerates each case exactly once.

**Heuristic / deferred (laws are weak, contextual, or require runtime instrumentation):**

- `Sendable` — value semantics is a heuristic, not a checkable invariant from outside the type. A `checkSendableContractLaws` Heuristic-tier suite (mutation-after-share spot checks) is a research item, not a v1.1 deliverable.
- `LazySequenceProtocol`, `LazyCollectionProtocol` — laziness *is* a property to test (no eager evaluation) but requires instrumentation hooks.
- `CustomStringConvertible`, `CustomDebugStringConvertible`, `TextOutputStreamable`, `TextOutputStream` — output formatting protocols; no semantic laws beyond "the conformance doesn't crash."
- `ExpressibleBy*` (the 10 literal protocols) — laws are structural rather than semantic; covered by the compiler's literal expansion.

**Permanently out of scope (no testable behavioral laws):**

- `AnyObject`, `AnyClass` — marker / class-constraint protocols.
- `Error`, `LocalizedError` — no behavioral contract beyond conformance and optional message accessors.
- `Encoder`, `Decoder`, `CodingKey` — infrastructure for `Codable` (which *is* covered).
- `CVarArg`, `MirrorPath`, `CustomReflectable` — bridging / reflection.
- `RandomNumberGenerator` — `next() -> UInt64` has no testable contract beyond the type signature.

Adding a new protocol's laws is a `LawRegistry` entry, not a structural change (§6 architecture). Community contributions for v1.1 protocols land in `ProtocolLawKit-Community` (§9 Decision 3).

### 4.4 Usage API

Protocol law checks are invoked as generic functions, ideally as Swift Testing traits so the test runner handles reporting and parallelization natively. The default backend is `swift-property-based`:

```swift
import ProtocolLawKit
import Testing

// Trait-based style (recommended; see §9 Decision 5):
@Test(.protocolLaws(Equatable.self, Comparable.self, budget: .standard))
func myTypeLaws() async throws { /* uses .derived generator */ }

// Or as explicit function calls:
@Suite struct MyTypeConformanceTests {

    @Test func equatableProtocolLaws() async throws {
        try await checkEquatableProtocolLaws(
            for: MyType.self,
            using: Gen.myType(),
            budget: .standard
        )
    }

    @Test func codableProtocolLaws() async throws {
        try await checkCodableProtocolLaws(
            for: MyType.self,
            using: Gen.myType(),
            mode: .strict,
            encoder: JSONEncoder(),
            decoder: JSONDecoder(),
            budget: .standard
        )
    }
}
```

#### Trial Budget Tiers

Property-based testing on `Collection` or recursive structures at 10,000 trials per protocol law per type can dominate CI time. Every check accepts a `budget`:

| Budget | Trials | Intended use |
|---|---|---|
| `.sanity` | 100 | Local pre-commit, fast feedback |
| `.standard` | 1,000 | Default; PR-level CI |
| `.exhaustive(n)` | n (default 10,000) | Nightly / release branches |
| `.custom(trials:)` | n | Explicit override |

#### Generic Conformances

Real Swift code is generic-heavy: `Array<T>: Equatable where T: Equatable`, `Result<Success, Failure>: Equatable where Success: Equatable, Failure: Equatable`, user-defined `Container<T>`, and so on. ProtocolLawKit checks generic conformances by binding type parameters at the call site:

```swift
// Conditional conformance on a user-defined container.
@Test func containerEquatableProtocolLaws() async throws {
    try await checkEquatableProtocolLaws(
        for: Container<Int>.self,
        using: Gen.container(of: Gen.int())
    )
    try await checkEquatableProtocolLaws(
        for: Container<String>.self,
        using: Gen.container(of: Gen.string())
    )
}
```

The Discovery plugin does *not* automatically enumerate generic instantiations — that's an unbounded search space and will produce noisy stubs. Instead, the developer registers representative bindings on the generic type:

```swift
@LawGenerator(bindings: [Container<Int>.self, Container<String>.self, Container<UUID>.self])
struct Container<T: Equatable>: Equatable { /* ... */ }
```

The plugin emits one stub per binding, with the binding listed in the generated comment header so reviewers see the exercised type set. Bindings can be added or removed in regenerated files; the regeneration-as-diff workflow (§5.3) preserves prior bindings as inline suppressions.

Failures report which specific protocol law was violated, the strictness tier, and an explicit "not a proof" disclaimer:

```
✗ Equatable.symmetry violated for MyType  [Strict, .standard]
  Counterexample: x = MyType(priority: 3), y = MyType(priority: 5)
  x == y evaluated to true, but y == x evaluated to false
  Replay with seed: aKPPWDEafU0CGMDYHef/ETcbYUyjWQvRVP1DTNy6qJk=
  (1,000 trials run; this is empirical evidence, not a proof.)
```

### 4.5 Backend Abstraction

ProtocolLawKit defines a `PropertyBackend` protocol so teams can swap the underlying runner. The signature accommodates async, throwing properties (the common case in Swift code under test) and `Sendable` types (Swift 6 strict concurrency):

```swift
public protocol PropertyBackend {
    func check<T: Sendable>(
        trials: Int,
        seed: Seed?,
        generator: Gen<T>,
        property: @Sendable (T) async throws -> Bool
    ) async throws -> CheckResult
}
```

The default implementation wraps `swift-property-based`. Alternative implementations can target SwiftQC or future backends without changing protocol law definitions.

**Deferred public abstraction.** Only two property-based backends in the Swift ecosystem are viable today (`swift-property-based`, SwiftQC), and their shrinking and async semantics differ. The protocol above is *internal* through M3. The public abstraction surface is finalized at M4 alongside the second backend implementation, so the API is shaped against two concrete implementations rather than one.

#### Actor-Isolated and Sendable Types

For an actor or actor-isolated type, the property closure runs on the type's actor; each trial pays one actor hop. Throughput is lower; correctness is unaffected. The `@Sendable` constraint on the property closure ensures inputs cross actor boundaries safely under Swift 6 strict concurrency.

Pure `Sendable` value types check identically to non-Sendable types — the constraint is satisfied at the closure boundary. The generator registry is implemented as an actor (not as `static var`) so generator lookup is concurrency-safe.

`Sendable`'s own informal contract — value semantics, no shared mutable state — is *not* a checkable v1 law (it would require runtime instrumentation to detect post-share mutation). A future `checkSendableContractLaws` Heuristic-tier suite is named in §4.3 Coverage Scope as a research item.

### 4.6 Confidence Reporting

Each protocol law check reports its result as a confidence artifact rather than a simple pass/fail:

```swift
CheckResult(
    protocolLaw: "Equatable.symmetry",
    tier: .strict,
    trials: 1_000,
    seed: "aKPPWDEafU0CGMDYHef/...",
    environment: .init(             // fingerprint for replay validity
        swiftVersion: "6.1",
        backend: "swift-property-based 0.4.2",
        generatorSchema: "abc123def..."   // hash of registered generators
    ),
    outcome: .passed,
    nearMisses: [],                 // inputs that came close to violating
    coverageHints: .init(           // approximate distribution insight
        inputClasses: ["zero": 12, "negative": 488, "positive": 500],
        boundaryHits: ["Int.min": 1, "Int.max": 1, "empty-string": 0]
    )
)
```

This positions protocol law checks as *replayable experiments* — the seed and trial count are part of the permanent test record. The optional `coverageHints` mitigates the "10,000 trials looks precise but is meaningless if all inputs are tiny integers" failure mode by recording which input classes the generator actually produced.

**Near-miss semantics.** A near-miss is an input where the property *almost* failed — surfacing brittleness even on green runs. Each protocol law defines its own criterion:

- `Equatable.symmetry` — inputs where the implementation took asymmetric code paths but happened to return the same boolean.
- `Equatable.transitivity` / `Comparable.transitivity` — triples where the relation barely held (within an epsilon for floating-point fields, or where ordering depended on tie-breaking that's not part of `<`).
- `Codable.roundTripFidelity` — values where decoded ≠ original on a single field, with the failing field's `KeyPath` reported.
- `Hashable` consistency — inputs that hashed differently across consecutive calls in the same process (a stability hint).
- `Collection` / `Sequence` count — iterators that yielded a count off-by-one from `count` / `underestimatedCount`.

Backends that don't expose this introspection report `nearMisses: nil` rather than an empty array, so callers distinguish "no near-misses" from "this backend doesn't track them."

**Environment fingerprinting.** A seed is only as replayable as the environment that produced it. `CheckResult.environment` records the Swift compiler version, the backend identity and version, and a hash of the registered generator schema. When a stored seed is replayed (e.g. from a CI artifact stored months earlier), ProtocolLawKit verifies the environment matches before running. On mismatch, replay fails with a clear diagnostic (`seed produced under Swift 6.1 + swift-property-based 0.4.2; current is 6.2 + 0.5.0 — generator schema also differs`) rather than silently re-rolling a different test under the same seed string.

Sample outputs at three outcomes:

```
✓ Equatable.reflexivity for MyType  [Strict, .standard]
  1,000 trials, no violations, no near-misses.
  Coverage: 412 default-init / 588 generated; boundaries hit: 7/8 declared.
  (Empirical evidence, not a proof.)

⚠ Codable.roundTripFidelity for MyType  [Conventional, .standard]
  1 near-miss in 1,000 trials (Date precision drift).
  Suggest: switch to .semantic(equivalent:) or pin Date precision.
  Replay with seed: 7Vh9...

✗ Comparable.transitivity violated for MyType  [Strict, .standard]
  Counterexample: a = MyType(rank: 1), b = MyType(rank: 4), c = MyType(rank: 2)
  Replay with seed: aKPP...
```

### 4.7 Suppression and Customization

The biggest adoption risk for any law-checking tool is developer frustration from false positives. ProtocolLawKit provides explicit, declarative suppression at three granularities:

```swift
// Per-type, per-law: suppress this single check on this single type.
@SuppressProtocolLaw(.equatable(.reflexivity), reason: "NaN by design")
struct MyFloatWrapper: Equatable { /* ... */ }

// Per-type: declare a type as intentionally violating a protocol's standard contract.
// Strict-tier checks still run, but reported as `.expectedViolation` rather than failure.
@IntentionalProtocolViolation(.equatable, scope: .reflexivityOnNaN)
struct PartialOrderType { /* ... */ }

// Per-call site: customize the equivalence used by Codable round-trip checking.
try await checkCodableProtocolLaws(
    for: Invoice.self,
    using: Gen.invoice(),
    mode: .semantic(equivalent: { $0.canonicalized == $1.canonicalized }),
    budget: .standard
)
```

Suppressions appear in the test report so reviewers can spot policy drift, and CI can assert that the suppression list does not grow unexpectedly (a `--max-suppressions=N` plugin flag).

### 4.8 Milestones

| Milestone | Deliverable |
|---|---|
| M1 | `Equatable` and `Hashable` protocol laws (Strict tier only), `swift-property-based` backend, diagnostic output, trial budgets |
| M2 | `Comparable` and `Codable` protocol laws; `Codable` strict/semantic/partial modes; Conventional tier introduced |
| M3 | `Collection` and `SetAlgebra` protocol laws; suppression and intentional-violation API |
| M4 | `PropertyBackend` public abstraction; SwiftQC backend; finalized async/throws/Sendable property signature |
| M5 | Confidence reporting upgrade — near-miss tracking, coverage hints, "not a proof" messaging, Heuristic tier |

-----

## 5. Contribution 2: ProtoLawMacro

### 5.1 Description

ProtoLawMacro is a tooling layer that uses SwiftSyntax to statically analyze source files, detect protocol conformances, and automatically generate ProtocolLawKit test registrations. It eliminates the need to manually write `checkEquatableProtocolLaws(...)` calls for each conforming type.

ProtoLawMacro outputs *human-reviewable stubs*, not silently executed tests. The developer reviews, approves, and commits generated test code. This preserves developer agency and avoids the "magic that occasionally breaks" failure mode.

### 5.2 Layered Scope

ProtoLawMacro is deliberately layered. The Core layer is the MVP — small, narrow, and the only thing required to deliver value. Advisory and Experimental layers are opt-in and ship later in the milestone sequence.

| Layer | Capabilities | Default state |
|---|---|---|
| **Core** | Conformance → test stub generation (per-suite macro/trait and discovery plugin) | Always on |
| **Advisory** | Missing-conformance suggestions; cross-function round-trip discovery | Off by default; CLI flag or config to enable |
| **Experimental** | Pattern warnings for known protocol law combinations; Codable-derived generators | Off by default; explicit opt-in per project |

The architecture diagram (§6) reflects this layering. Users adopting only Core get a deterministic, low-noise tool. Advisory and Experimental can be evaluated independently without affecting Core's signal-to-noise ratio.

### 5.3 Core: Two Operating Modes

#### Macro Mode (compile-time, per-suite)

A single annotation on a test triggers protocol law generation for the named types. This is best expressed as a Swift Testing trait so the runner integrates law checks naturally:

```swift
@Test(.protocolLaws(MyType.self, OtherType.self))
func conformanceLaws() async throws { /* expanded at compile time */ }

// Equivalent freestanding macro form (for non-Swift-Testing contexts):
@ProtoLawSuite(types: [MyType.self, OtherType.self])
struct AutoProtocolLawTests {}
```

The macro/trait expands to the appropriate `checkXxxProtocolLaws(...)` calls based on the detected conformances of each named type at compile time.

#### Discovery Mode (Swift Package Plugin, whole-module)

Whole-module discovery is delivered as a **Swift Package Plugin**, not a macro: macros are file-local and cannot scan a module's other files, while a build-tool plugin has the file-system access required.

```bash
swift package protolawcheck discover --target MyModule --output ProtocolLawTests.generated.swift
```

Output is clearly marked as generated and includes provenance:

```swift
// GENERATED by swift-package protolawcheck — review before committing
// Detected conformances: Equatable, Comparable, Codable
// Source: Sources/MyModule/MyType.swift
//
// Note: Comparable extends Equatable, so checkComparable runs Equatable's
// laws automatically (see §4.3 inheritance semantics). One call per type,
// most specific wins.

@Suite struct MyTypeProtocolLaws {

    // Comparable + inherited Equatable laws — MyType: Comparable (line 13, MyType.swift)
    @Test func comparableProtocolLaws() async throws {
        try await checkComparableProtocolLaws(for: MyType.self, using: .derived)
    }

    // Codable protocol laws — MyType: Codable (line 14, MyType.swift)
    @Test func codableProtocolLaws() async throws {
        try await checkCodableProtocolLaws(
            for: MyType.self,
            using: .derived,
            mode: .strict,
            encoder: JSONEncoder(), decoder: JSONDecoder()
        )
    }
}
```

#### Developer Workflow

1. Run the discovery plugin (locally or wired into CI).
2. Review the generated `*.generated.swift` file as a normal PR.
3. Commit the generated file. Re-run the plugin when types or conformances change; subsequent runs produce a *diff* against the existing generated file rather than overwriting suppressions or hand edits.
4. Suppress noisy or wrong suggestions inline (in the generated file) with comments the next regeneration honors. Suppression deltas show up in diff review.

### 5.4 Advisory: Missing Conformance Suggestions (opt-in)

Beyond verifying declared conformances, ProtoLawMacro can suggest *potentially missing* conformances based on structural analysis. **This is opt-in (`--advisory` flag), not default.** It is informational output, never a test failure:

```
ℹ️  MyType has encode(_:) and init(from:) but does not declare Codable.
    Consider conforming and running codableProtocolLaws to verify round-trip fidelity.

ℹ️  MyType has a binary + operator and a zero static property.
    This matches the Monoid pattern. Consider formalizing with AdditiveArithmetic.
```

Suggestions carry a confidence score (Low / Medium / High); only High by default, to keep noise low. Suggestions are conservative — only emitted when structural evidence is strong — and always require human judgment to act on.

### 5.5 Advisory: Cross-Function Discovery (opt-in)

ProtoLawMacro can detect function pairs with inverse type signatures and suggest round-trip properties:

- Detection criteria: functions `f: T → U` and `g: U → T` in the same type or module.
- Filtered by: type compatibility first, naming heuristics second (`encode`/`decode`, `serialize`/`deserialize`, `push`/`pop`).
- Optional grouping hint to reduce noise: `@Discoverable(group: "serialization")`.

Cross-function discovery is opt-in to manage signal-to-noise ratio.

### 5.6 Experimental: Pattern Warnings for Known Combinations

When multiple protocol law annotations are applied to the same function or type, ProtoLawMacro can emit *pattern warnings* drawn from a small, curated table of known combinations. **This is not a logical-contradiction-detection system; it does not aspire to soundness or completeness.** It is a fixed list of patterns the maintainers have seen produce surprising test outcomes in practice.

```swift
@CheckProtocolLaws([.idempotent, .involutive])
func normalize(_ x: MyType) -> MyType { /* ... */ }
```

Triggers:

```
⚠️  Pattern warning: .idempotent + .involutive applied to the same function imply f is identity.
    If that is intentional, suppress with @CheckProtocolLaws(..., suppressPatterns: [.idempotentInvolutive]).
```

Patterns are small, curated, and named individually. No graph reasoning. Adding a new pattern requires a maintainer commit, not implicit derivation.

### 5.7 Generator Derivation

Generator derivation is the single highest execution risk in this proposal — a weak generator produces green tests that are not meaningful, defeating the entire premise. ProtoLawMacro's `.derived` strategy is therefore explicit, prioritized, and produces *visible warnings* when coverage is likely insufficient.

#### Derivation Priority Order

For type `T`, ProtoLawMacro tries strategies in this order, falling through to the next on failure:

1. **Explicit registration** — a `Gen<T>` provided by the developer, looked up in a process-wide registry.
2. **`CaseIterable`** — enumerate cases. Strong distribution.
3. **All-`Arbitrary` memberwise init** — compose generators for each parameter. Strong distribution.
4. **`RawRepresentable` with `Arbitrary` `RawValue`** — lift the raw-value generator.
5. **`Codable` round-trip from a sample literal** — only when explicitly enabled (`--allow-codable-derivation`); produces a "weak generator" warning because the distribution clusters around defaults and misses boundary cases. *Experimental layer.*
6. **No generator available** — emit a `.todo` stub that does *not* compile until replaced. This is deliberate — silent fallthrough is more dangerous than a compile error.

#### Recursive Types

For recursive types (`indirect enum`, struct that contains itself in an array, etc.), ProtoLawMacro:

- Detects recursion at derivation time.
- Requires either an explicit `Gen<T>` or a `@RecursionLimit(_)` annotation.
- Refuses to derive without one, rather than silently producing a generator that diverges or always returns the base case.

#### Override Mechanism

The developer always wins. Annotating a type with `@LawGenerator(custom: Gen.myType)` shadows the derived generator everywhere ProtoLawMacro emits a stub for that type.

#### Failure Telemetry

When derivation falls back to `.todo` or emits a "weak generator" warning, the discovery plugin records which type, which strategy was attempted, and why it failed. This telemetry surfaces in the plugin's summary report so weak coverage is visible, not buried.

### 5.8 Milestones

| Milestone | Deliverable | Layer |
|---|---|---|
| M1 | SwiftSyntax conformance detection, `@ProtoLawSuite` macro and `.protocolLaws(...)` trait, diagnostic emission | Core |
| M2 | Swift Package Plugin discovery mode, generated file output with provenance, regeneration-as-diff workflow | Core |
| M3 | Generator derivation with priority order, recursion handling, `.todo` stubs, weak-generator telemetry | Core |
| M4 | Missing-conformance suggestions (opt-in, confidence-scored) | Advisory |
| M5 | Cross-function round-trip discovery (opt-in) | Advisory |
| M6 | Pattern warnings for known protocol law combinations; `Codable`-derived generators behind opt-in flag | Experimental |

-----

## 6. Architecture Overview

```
┌─────────────────────────────────────────────────┐
│                  ProtoLawMacro                  │
│  Core: SwiftSyntax + @ProtoLawSuite +           │
│        .protocolLaws(...) trait + Plugin CLI    │
│  Advisory: missing-conformance, cross-function  │
│  Experimental: pattern warnings                 │
└────────────────┬────────────────────────────────┘
                 │ generates calls into
┌────────────────▼────────────────────────────────┐
│                 ProtocolLawKit                  │
│  ┌───────────────────────────────────────────┐  │
│  │            LawRegistry                    │  │
│  │  Equatable / Hashable / Comparable /      │  │
│  │  Codable / Collection / SetAlgebra        │  │
│  │  Each protocol law has a strictness tier  │  │
│  └───────────────────────────────────────────┘  │
│  Suppression API · Confidence reporting         │
│  Trial budgets · Coverage hints                 │
└────────────────┬────────────────────────────────┘
                 │ runs via
┌────────────────▼────────────────────────────────┐
│                 PropertyBackend                 │
│  swift-property-based (default)                 │
│  SwiftQC (M4)                                   │
│  async / throws / Sendable property closures    │
└─────────────────────────────────────────────────┘
```

The named **LawRegistry** layer makes the extension point explicit: adding a new protocol's laws is a registry entry, not a structural change. The strictness tier per protocol law is a property of the registry entry, not a runtime flag.

-----

## 7. Risks and Mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| Developer frustration from false positives kills adoption | High | Strictness tiers (§4.2) demote conventional/heuristic checks; suppression API (§4.7) provides per-type, per-law, and intentional-violation escape hatches; tools can assert the suppression list does not grow unexpectedly. |
| Weak generators produce green tests that miss real bugs | High | Derivation is prioritized and visible (§5.7); fallback emits `.todo` stubs that don't compile; weak-generator warnings surface in the report; `CheckResult.coverageHints` records actual distribution. |
| Swift macro / plugin diagnostics UX is poor | Medium | Diagnostic quality is a first-class M1 deliverable; trial output includes the strictness tier and a "not a proof" disclaimer. |
| Generated tests are noisy / low signal | Medium | Layered scope (Core / Advisory / Experimental); Advisory and Experimental are off by default; regeneration-as-diff so suppressions persist. |
| Cross-function pairing is O(n²) at scale | Low | Type-directed filtering; cross-function discovery is Advisory and off by default. |
| Recursive monorepo discovery is slow | Medium | Plugin caches conformance scan per file; `--changed-only` flag scopes to files changed in the current PR/branch. |
| Backend divergence (seed / generator mismatch between backends) | Low | Public `PropertyBackend` abstraction deferred until M4 so it's shaped against two concrete backends; explicit seed contract. |
| Pattern warnings misread as "logical contradiction proofs" | Low | §5.6 is reframed as a curated, named-pattern list; documentation does not claim soundness or completeness. |
| Checkbox testing — green output assumed to mean correctness | Medium | Every pass output carries an explicit "empirical evidence, not a proof" disclaimer (§4.6). |

-----

## 8. Success Criteria

### ProtocolLawKit

- A developer can add protocol law checking for a custom `Equatable` type in under 5 minutes (UX criterion).
- Protocol law violations produce failure messages that identify the specific violated protocol law, its strictness tier, and a reproducible counterexample (replayable seed).
- The protocol law library compiles and passes CI on Linux, macOS, and Windows.
- **Framework self-test gate (every CI run).** ProtocolLawKit ships a planted-bug suite: types deliberately violating each Strict law, asserted to be detected by the framework. A green CI run requires every planted violation to be caught at the expected strictness tier. This catches regressions in the framework itself — without it, a bug that silences the symmetry check would pass CI undetected.
- **External validation gate (must hit before 1.0).** Three artifacts in `Validation/`, each demonstrating one face of the kit's pipeline against external real-world Swift code:

  1. **Pass 1 — discovery scan.** The `protolawcheck discover` plugin emits law-check scaffolding for **at least four real-world Swift packages** without crashes, malformed output, or false-positive duplicate suites. Generated files plus per-package `.todo` summaries are checked into `Validation/results/`.
  2. **Pass 2 — composition.** The kit composes with at least one external SwiftPM dependency and runs at least one Strict-tier law check end-to-end against a public type from that package, with the test target green under `swift test`.
  3. **Pass 3 — archaeology.** A git-archaeology survey of fix-commits across full-history Swift packages, with results documented in `Validation/FINDINGS.md`. The artifact is the documented search effort and any candidate bugs found — *regardless of whether the kit catches them*. A null result is a valid Pass 3 outcome and counts toward the gate, provided the search method, surveyed corpus, and rejection rationale are all in the repository.

  **Why this replaces v0.2's "catch a real bug in 5+ packages" criterion.** The v0.2 wording set retroactive bug-discovery in already-shipped popular code as the bar for shipping 1.0. Empirically — see `Validation/FINDINGS.md` Pass 3 — that bar is approximately uncloseable: across ~5,200 commits surveyed in four full-history Apple/SSWG/community packages (`swift-argument-parser`, `swift-aws-lambda-runtime`, `swift-collections`, `swift-nio`, `hummingbird`), exactly one candidate fix-commit survived initial filtering, and on inspection the bug was in dead code unreachable through the public API. The structural reasons are clear: well-tested Swift OSS leans on synthesized conformances (bulletproof by construction); hand-written conformances in scrutinized code land correct on first commit and rarely get patched; the population of historical kit-detectable bugs in well-tested packages is approximately empty. The kit's value prop is therefore *prevention* — catching bugs in new code as it's written, before they ship — not retroactive *discovery* in code that's already been hammered by years of users. The v0.3 gate measures what the kit can actually deliver: pipeline composition (Pass 1+2) plus an honest, documented search effort (Pass 3).

### ProtoLawMacro

- The discovery plugin correctly identifies conformances in a real-world Swift module with less than 5% false-positive *Strong*-confidence suggestions in the Advisory layer.
- Generated test stubs for types with derivable generators compile without modification.
- For types where derivation is uncertain, the plugin always emits a non-compiling `.todo` stub or a visible weak-generator warning — never a silently green test.
- Pattern warnings catch the idempotent/involutive case and at least two other curated patterns.

-----

## 9. Resolved Decisions

These were Open Questions in v0.1; v0.2 commits to a direction.

1. **Naming.** `SwiftProtocolLaws` (umbrella) / `ProtocolLawKit` (library target) / `ProtoLawMacro` (tooling target). **Single repository, multiple targets.** ProtoLawMacro is too tightly coupled to the ProtocolLawKit API for separate-repo versioning to be worth the overhead.
2. **Generator convention.** **Explicit `Gen<T>` is required by default.** `.derived` is opt-in via `using: .derived` (or via the Discovery plugin, which always emits explicit derivation calls reviewers can audit). When `.derived` fails, the failure mode is a non-compiling `.todo` stub or a visible weak-generator warning — never silent fallthrough. The "magic" path is opt-in.
3. **Conformance scope.** v1 ships only the standard-library protocols enumerated in §4.3. Common third-party protocols (`Identifiable`, custom algebraic structures) are deferred to a community-contributed target (`ProtocolLawKit-Community`) to keep the core library's law set audited and stable.
4. **Macro vs. Swift Package Plugin for discovery.** **Both, with clear roles.** `@ProtoLawSuite` (and the Swift Testing `.protocolLaws(...)` trait) remain compile-time macros for per-suite, per-type wiring. **Whole-module discovery is a Swift Package Plugin**, not a macro — macros cannot read other files in the module, and the plugin model is purpose-built for this access pattern.
5. **Relationship to swift-testing.** **`@ProtoLawSuite` is implemented as a Swift Testing custom Trait** (`@Test(.protocolLaws(Equatable.self, ...))`). The trait composes naturally with Swift Testing's reporting, filtering, parallelization, and `.disabled(...)` ergonomics rather than reinventing them. The freestanding `@ProtoLawSuite(types:)` macro form remains available for non-Swift-Testing contexts.

Remaining open question, deferred to a future revision:

- **Stateful / model-based testing.** Hedgehog-style state-machine testing for protocols like `Collection` or `MutableCollection` would catch a different class of bug than property-per-trial testing. v1 explicitly excludes this; whether v2 adopts a state-machine layer remains open.

-----

## 10. References

- [swift-property-based](https://github.com/x-sheep/swift-property-based) — primary backend target
- [SwiftQC](https://github.com/Aristide021/SwiftQC) — alternative backend
- [SwiftCheck](https://github.com/typelift/SwiftCheck) — prior art, now dormant
- [QuickCheck](https://hackage.haskell.org/package/QuickCheck) and `quickcheck-classes` — Haskell prior art (law libraries are the closest analog to ProtocolLawKit)
- [proptest](https://github.com/proptest-rs/proptest) and the `arbitrary` derive — Rust prior art (`arbitrary` is the closest analog to `.derived` generator derivation)
- [Hedgehog](https://hackage.haskell.org/package/hedgehog) — state-machine testing reference (deferred to v2 scope)
- [EvoSuite](https://www.evosuite.org) — Java property inference inspiration
- [Daikon](https://plse.cs.washington.edu/daikon/) — runtime invariant inference reference
- Swift Evolution [SE-0185](https://github.com/apple/swift-evolution/blob/main/proposals/0185-synthesize-equatable-hashable.md) — synthesized protocol conformances

-----

## Appendix A: Changelog vs. v0.2

v0.3 is a tightly-scoped revision: one criterion rewritten, one protocol's law set expanded, three minor wording catch-ups. No new milestones, no architectural change.

**Tier 1 — criterion calibration:**

- **§8 Validation criterion rewritten.** v0.2's "catch a real bug in 5+ popular Swift packages before 1.0" is replaced with the **External validation gate**: three documented artifacts in `Validation/` (Pass 1 discovery scan over ≥4 packages, Pass 2 composition with ≥1 external SwiftPM dep, Pass 3 git-archaeology with results in FINDINGS.md). A null Pass 3 outcome is a valid result. See §8 for the full rationale and `Validation/FINDINGS.md` for the empirical evidence that drove the rewrite.

**Tier 2 — coverage expansion:**

- **§4.3 SetAlgebra expanded from five laws to nine.** The four `symmetricDifference*` laws (`symmetricDifferenceSelfIsEmpty`, `symmetricDifferenceEmptyIdentity`, `symmetricDifferenceCommutativity`, `symmetricDifferenceDefinition`) were added in response to the Pass 3 archaeology surfacing a `swift-collections` typo fix in `_Bitmap.symmetricDifference`. The original five-law suite did not exercise the `symmetricDifference` operation at all. All four new laws ship at the Strict tier.

**Tier 3 — wording / scope catch-ups:**

- **§8 framework self-test gate** retained verbatim from v0.2. v0.3 does not change the kit's CI guarantees; it changes only how 1.0-readiness is *measured against external code*.
- **Appendix A renumbering.** The v0.2 → v0.1 changelog moves to Appendix B. v0.3's changelog (this section) takes the Appendix A slot, so a reader of the latest PRD encounters the most recent calibration first.

**What v0.3 does *not* change:**

- §4.2 Strictness tiers, §4.4 trial budgets, §4.5 backend abstraction, §4.6 confidence reporting, §4.7 suppression, §4.8 milestones — all carry forward unchanged.
- §5.* ProtoLawMacro (Core / Advisory / Experimental layering, derivation priority, plugin-vs-macro split) — unchanged. M4–M6 remain on the roadmap with the same scope they had in v0.2.
- §9 Resolved Decisions — unchanged. The single-backend-by-design decision (made post-v0.2 in `74fb9f2`) was implementation-level rather than scope-level and lives in `CLAUDE.md`'s repo-state notes; it does not require a PRD-level resolution.

-----

## Appendix B: Changelog vs. v0.1

**Tier 1 — consensus changes from external critique (raised by 2+ reviewers):**

- **§4.2 (new)**: Strictness tiers (Strict / Conventional / Heuristic) classify every protocol law and govern default failure behavior.
- **§4.3**: Tier column added to all six protocol law tables; `Codable` round-trip exposes `.strict` / `.semantic(equivalent:)` / `.partial(fields:)` modes.
- **§5.2 (new)**: Layered scope — Core / Advisory / Experimental — with Advisory and Experimental features off by default. Missing-conformance suggestions and cross-function discovery move to Advisory.
- **§5.7**: Generator derivation expanded with explicit priority order, recursive-type handling, override mechanism, and weak-generator telemetry.

**Tier 2 — substantive single-reviewer changes:**

- **§4.5**: `PropertyBackend.check` signature now `@Sendable (T) async throws -> Bool` returning `async throws -> CheckResult`; explicit deferral of the public abstraction surface to M4.
- **§4.4**: Trial budget tiers (`.sanity` / `.standard` / `.exhaustive` / `.custom`).
- **§4.7 (new)**: Suppression and customization API — per-type, per-law, intentional-violation, custom equivalence.
- **§5.6**: Property contradiction detection reframed as "pattern warnings for known combinations" — curated, not derived; explicitly disclaims soundness.
- **§9 Decision 4**: Whole-module discovery committed to a Swift Package Plugin, not a macro.
- **§9 Decision 5**: `@ProtoLawSuite` implemented as a Swift Testing custom Trait.
- **§8**: Real-world validation criterion added — must catch a real bug in 5+ popular Swift packages before 1.0.

**Tier 3 — strategic / polish:**

- **§1.1 (new)**: "Why Now" section.
- **§1**: Killer-use-case anchor sentence.
- **§2.3**: Explicit positioning vs. Rust `proptest` and Haskell QuickCheck.
- **§4.6**: Sample reports for pass / near-miss / fail outcomes; "not a proof" disclaimer; coverage hints in `CheckResult`.
- **§5.3**: Developer Workflow subsection (regeneration-as-diff, suppression deltas).
- **§6**: Architecture diagram surfaces a named `LawRegistry` layer.
- **§7**: New risks added — adoption-killing false positives; recursive monorepo discovery; pattern-warning misinterpretation; checkbox-testing.
- **§9**: Open Questions become Resolved Decisions with committed directions.
- **§10**: References sharpened to identify each prior art's role (law libraries, `arbitrary` derive, state-machine testing).

**Beyond the external critiques — own design pass:**

Items the three external critiques did not raise but which v0.2 also addresses, identified during a follow-up review:

- **§4.3 inheritance semantics.** `checkXxxProtocolLaws` runs the inherited suites by default (`checkHashable` runs Equatable's laws; `checkComparable` runs Equatable's; `checkCollection` runs Sequence's and IteratorProtocol's). `.ownOnly` is the opt-out. Property tests are too expensive to make "remember to chain" the user's responsibility, and forgetting to chain is a silent way to miss real semantic bugs. The Discovery plugin emits the most specific call per type, so generated tests don't double-run inherited laws.
- **§4.3 IteratorProtocol and Sequence laws.** Added; v0.1 had `Collection` without its dependencies. The §4.3 Coverage Scope subsection now enumerates what's in v1, what's a v1.1 candidate, what's heuristic/deferred, and what's permanently out of scope (cross-referenced against `docs/Swift Standard Library Protocols.md`).
- **§4.3 `Codable.partial(fields:)` typed as `[PartialKeyPath<T>]`** rather than `[String]` — type-safe, refactor-safe.
- **§4.4 Generic Conformances.** Conditional / generic conformances are checked by binding type parameters at the call site; the Discovery plugin requires explicit `@LawGenerator(bindings: ...)` rather than enumerating the unbounded space.
- **§4.5 Actor-Isolated and Sendable Types.** Spelled out: actor hop per trial, Sendable closures, registry implemented as an actor for Swift 6 concurrency safety. Sendable's value-semantics contract is explicitly named as a deferred research item.
- **§4.6 near-miss semantics defined.** Per-protocol criterion table, plus `nearMisses: nil` to distinguish "no near-misses" from "backend doesn't track them."
- **§4.6 environment fingerprint on `CheckResult`.** Replay verifies Swift version, backend version, and generator-schema hash; a stale seed fails loudly instead of silently replaying a different test.
- **§8 framework self-test gate.** Planted-bug suite asserts the framework itself catches every Strict violation on every CI run — guards against regressions in the law-checker.
