# Product Requirements Document

## SwiftPropertyLaws: Protocol Law Testing for Swift

**Version:** 0.1 Draft  
**Status:** Proposal  
**Audience:** Open Source Contributors, Swift Ecosystem

-----

## 1. Overview

Swift’s protocol system creates a gap between structural conformance — which the compiler verifies — and semantic conformance, which it cannot. A type may declare `Equatable` while implementing `==` incorrectly. A `Comparable` implementation may violate transitivity. A `Codable` round-trip may silently lose data. None of these violations are detectable at compile time.

This document proposes **SwiftPropertyLaws**, an open source Swift package delivering two separable but complementary contributions:

- **Contribution 1 — PropertyLawKit**: A curated library of protocol law property tests, generic over any conforming type, usable standalone with any property-based testing backend.
- **Contribution 2 — PropertyLawMacro**: A Swift macro layer that uses SwiftSyntax to detect protocol conformances in a codebase and automatically wire up PropertyLawKit tests, eliminating manual test registration.

These two contributions are intentionally decoupled. PropertyLawKit ships first and has independent value. PropertyLawMacro depends on PropertyLawKit and adds automation.

-----

## 2. Problem Statement

### 2.1 The Structural/Semantic Gap

Swift’s compiler enforces the *structural* contract of a protocol — the required methods and properties exist with correct signatures. It does not and cannot enforce the *semantic* contract — the behavioral protocol laws that a correct implementation is expected to satisfy.

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

- Translating prose specifications (the `Equatable` documentation) into property tests requires deliberate effort per type
- No standard library of protocol law checks exists for Swift
- The connection between protocol conformance and testable properties is implicit, not surfaced by tooling

### 2.3 The Ecosystem Gap

The Swift property-based testing ecosystem has two active packages (swift-property-based, SwiftQC) providing generation and shrinking infrastructure. Neither provides a protocol law library. No existing Swift tool connects protocol conformance declarations to property test generation. This gap is unoccupied.

-----

## 3. Goals and Non-Goals

### Goals

- Provide a complete, accurate library of semantic protocol law checks for Swift’s core protocols
- Make protocol law checking available to any Swift project with a one-line addition per type
- Integrate naturally with swift-property-based as the default backend
- Design the backend integration as an abstraction, not a hard dependency
- Provide a macro layer that eliminates manual protocol law registration through static analysis
- Surface missing protocol conformances as suggestions, not just verify existing ones
- Produce human-reviewable output, not silent automatic test generation

### Non-Goals

- Replacing unit tests or general property-based testing
- Supporting stateful / model-based testing (this is a separate project scope)
- Formal verification
- Full EvoSuite parity (domain-specific property inference is out of scope for v1)
- Automatic code fixing of detected protocol law violations

-----

## 4. Contribution 1: PropertyLawKit

### 4.1 Description

PropertyLawKit is a standalone Swift package providing a typed registry of protocol law property tests. Each law is expressed as a generic function parameterized over a conforming type, runnable against any property-based testing backend through a thin abstraction protocol.

### 4.2 Supported Protocol Laws

#### `Equatable`

|Protocol Law        |Description                           |
|--------------------|--------------------------------------|
|Reflexivity         |`x == x` for all `x`                  |
|Symmetry            |`x == y` implies `y == x`             |
|Transitivity        |`x == y` and `y == z` implies `x == z`|
|Negation consistency|`x != y` iff `!(x == y)`              |

#### `Hashable` (extends Equatable protocol laws)

|Protocol Law             |Description                                  |
|-------------------------|---------------------------------------------|
|Hash/equality consistency|`x == y` implies `x.hashValue == y.hashValue`|

#### `Comparable` (extends Equatable protocol laws)

|Protocol Law        |Description                            |
|--------------------|---------------------------------------|
|Antisymmetry        |`x <= y` and `y <= x` implies `x == y` |
|Transitivity        |`x <= y` and `y <= z` implies `x <= z` |
|Totality            |`x <= y` or `y <= x` for all `x`, `y`  |
|Operator consistency|`>`, `>=`, `<` are consistent with `<=`|

#### `Codable`

|Protocol Law        |Description                                            |
|--------------------|-------------------------------------------------------|
|Round-trip fidelity |`decode(encode(x)) == x` for all `x`                   |
|Encoder independence|Round-trip holds for all standard encoder/decoder pairs|

#### `Collection`

|Protocol Law     |Description                                              |
|-----------------|---------------------------------------------------------|
|Count consistency|`count` matches number of iterated elements              |
|Index validity   |All indices between `startIndex` and `endIndex` are valid|
|Non-mutation     |Iteration does not modify the collection                 |

#### `SetAlgebra`

|Protocol Law              |Description                             |
|--------------------------|----------------------------------------|
|Union idempotence         |`x.union(x) == x`                       |
|Intersection idempotence  |`x.intersection(x) == x`                |
|Union commutativity       |`x.union(y) == y.union(x)`              |
|Intersection commutativity|`x.intersection(y) == y.intersection(x)`|
|Empty identity            |`x.union(.empty) == x`                  |

### 4.3 Usage API

Protocol law checks are invoked as generic functions. The default backend is swift-property-based:

```swift
import PropertyLawKit
import Testing

@Suite struct MyTypeConformanceTests {

    @Test func equatablePropertyLaws() async {
        await checkEquatablePropertyLaws(
            for: MyType.self,
            using: Gen.myType()
        )
    }

    @Test func comparablePropertyLaws() async {
        await checkComparablePropertyLaws(
            for: MyType.self,
            using: Gen.myType()
        )
    }

    @Test func codablePropertyLaws() async {
        await checkCodablePropertyLaws(
            for: MyType.self,
            using: Gen.myType(),
            encoder: JSONEncoder(),
            decoder: JSONDecoder()
        )
    }
}
```

Failures report which specific protocol law was violated, not just that a property test failed:

```
✗ Equatable.symmetry violated for MyType
  Counterexample: x = MyType(priority: 3), y = MyType(priority: 5)
  x == y evaluated to true, but y == x evaluated to false
  Replay with seed: aKPPWDEafU0CGMDYHef/ETcbYUyjWQvRVP1DTNy6qJk=
```

### 4.4 Backend Abstraction

PropertyLawKit defines a `PropertyBackend` protocol so teams can swap the underlying runner:

```swift
public protocol PropertyBackend {
    func check<T>(
        trials: Int,
        seed: Seed?,
        generator: Gen<T>,
        property: (T) -> Bool
    ) async -> CheckResult
}
```

The default implementation wraps swift-property-based. Alternative implementations can target SwiftQC or future backends without changing protocol law definitions.

### 4.5 Confidence Reporting

Each protocol law check reports its result as a confidence artifact rather than a simple pass/fail:

```swift
CheckResult(
    protocolLaw: "Equatable.symmetry",
    trials: 10_000,
    seed: "aKPPWDEafU0CGMDYHef/...",
    outcome: .passed,
    nearMisses: []  // inputs that came close to violating
)
```

This positions protocol law checks as *replayable experiments* — the seed and trial count are part of the permanent test record.

### 4.6 Milestones

|Milestone|Deliverable                                                                     |
|---------|--------------------------------------------------------------------------------|
|M1       |`Equatable` and `Hashable` protocol laws, swift-property-based backend, diagnostic output|
|M2       |`Comparable` and `Codable` protocol laws                                                 |
|M3       |`Collection` and `SetAlgebra` protocol laws                                              |
|M4       |`PropertyBackend` abstraction, SwiftQC backend                                  |
|M5       |Confidence reporting, near-miss tracking                                        |

-----

## 5. Contribution 2: PropertyLawMacro

### 5.1 Description

PropertyLawMacro is a Swift macro package that uses SwiftSyntax to statically analyze source files, detect protocol conformances, and automatically generate PropertyLawKit test registrations. It eliminates the need to manually write `checkEquatablePropertyLaws(...)` calls for each conforming type.

PropertyLawMacro outputs *human-reviewable stubs*, not silently executed tests. The developer reviews, approves, and commits generated test code. This preserves developer agency and avoids the “magic that occasionally breaks” failure mode.

### 5.2 Two Operating Modes

#### Macro Mode (compile-time, per-type)

A single annotation on a test suite triggers protocol law generation for types under test:

```swift
@PropertyLawSuite(types: [MyType.self, OtherType.self])
struct AutoPropertyLawTests {}
```

The macro expands to the appropriate `checkXxxPropertyLaws(...)` calls based on the detected conformances of each named type at compile time.

#### Discovery Mode (CLI, whole-module)

A command-line tool scans a Swift module, enumerates all types with relevant protocol conformances, and emits a candidate test file for human review:

```bash
swift-propertylawcheck discover --target MyModule --output PropertyLawTests.generated.swift
```

Output is clearly marked as generated and includes provenance:

```swift
// GENERATED by swift-propertylawcheck — review before committing
// Detected conformances: Equatable, Comparable, Codable
// Source: Sources/MyModule/MyType.swift

@Suite struct MyTypePropertyLaws {

    // Equatable protocol laws — MyType: Equatable (line 12, MyType.swift)
    @Test func equatablePropertyLaws() async {
        await checkEquatablePropertyLaws(for: MyType.self, using: .derived)
    }

    // Codable protocol laws — MyType: Codable (line 14, MyType.swift)
    @Test func codablePropertyLaws() async {
        await checkCodablePropertyLaws(for: MyType.self, using: .derived,
                               encoder: JSONEncoder(), decoder: JSONDecoder())
    }
}
```

### 5.3 Missing Conformance Suggestions

Beyond verifying declared conformances, PropertyLawMacro performs structural analysis to suggest *potentially missing* conformances. This is surfaced as informational output, never as a test failure:

```
ℹ️  MyType has encode(_:) and init(from:) but does not declare Codable.
    Consider conforming and running codablePropertyLaws to verify round-trip fidelity.

ℹ️  MyType has a binary + operator and a zero static property.
    This matches the Monoid pattern. Consider formalizing with AdditiveArithmetic.
```

Suggestions are conservative — only emitted when structural evidence is strong — and always require human judgment to act on.

### 5.4 Property Contradiction Detection

When multiple protocol law annotations are applied to the same type, PropertyLawMacro checks for logical contradictions before emitting tests:

```swift
@CheckPropertyLaws([.idempotent, .involutive])  // f(f(x)) == f(x) AND f(f(x)) == x → f must be identity
func normalize(_ x: MyType) -> MyType { ... }
```

Contradictory combinations emit a warning:

```
⚠️  .idempotent and .involutive together imply the function is identity.
    Verify this is intentional before proceeding.
```

### 5.5 Cross-Function Discovery

PropertyLawMacro detects function pairs with inverse type signatures and suggests round-trip properties:

- Detection criteria: functions `f: T → U` and `g: U → T` in the same type or module
- Filtered by: type compatibility first, naming heuristics second (`encode`/`decode`, `serialize`/`deserialize`, `push`/`pop`)
- Optional grouping hint to reduce noise: `@Discoverable(group: "serialization")`

Cross-function discovery is opt-in in v1 to manage signal-to-noise ratio.

### 5.6 Generator Derivation

PropertyLawMacro attempts to derive generators for discovered types automatically using the `.derived` strategy:

- If `T: CaseIterable`, enumerate cases
- If `T: Codable`, use JSON round-trip generation
- If `T` has an `init` with all-`Arbitrary` parameters, compose generators
- Otherwise, emit a stub requiring a human-provided generator

### 5.7 Milestones

|Milestone|Deliverable                                                              |
|---------|-------------------------------------------------------------------------|
|M1       |SwiftSyntax conformance detection, `@PropertyLawSuite` macro, diagnostic emission|
|M2       |Discovery CLI, generated file output with provenance                     |
|M3       |Missing conformance suggestions                                          |
|M4       |Cross-function round-trip discovery (opt-in)                             |
|M5       |Property contradiction detection                                         |
|M6       |Generator derivation strategies                                          |

-----

## 6. Architecture Overview

```
┌─────────────────────────────────────────────────┐
│                  PropertyLawMacro                  │
│  SwiftSyntax analysis + @PropertyLawSuite macro    │
│  Discovery CLI + suggestion engine              │
└────────────────┬────────────────────────────────┘
                 │ generates calls to
┌────────────────▼────────────────────────────────┐
│                 PropertyLawKit                  │
│  Protocol law definitions                       │
│  checkEquatablePropertyLaws(), etc.             │
│  Confidence reporting                           │
└────────────────┬────────────────────────────────┘
                 │ runs via
┌────────────────▼────────────────────────────────┐
│                 PropertyBackend                 │
│  swift-property-based (default)                 │
│  SwiftQC (alternative)                          │
└─────────────────────────────────────────────────┘
```

-----

## 7. Risks and Mitigations

|Risk                                        |Likelihood|Mitigation                                                                   |
|--------------------------------------------|----------|-----------------------------------------------------------------------------|
|Swift macro diagnostics UX is poor          |Medium    |Prioritize diagnostic quality in M1; treat as first-class feature            |
|Generated tests are noisy / low signal      |Medium    |Human review gate on all generated output; conservative suggestion thresholds|
|Generator derivation fails silently         |Medium    |Always emit explicit stubs when derivation is uncertain                      |
|Cross-function pairing is O(n²) at scale    |Low       |Type-directed filtering eliminates most pairs before enumeration             |
|Backend divergence (seed/generator mismatch)|Low       |Shared `PropertyBackend` abstraction with explicit seed contract             |
|Property contradictions confuse users       |Low       |Contradiction detection in PropertyLawMacro with clear warnings                      |

-----

## 8. Success Criteria

### PropertyLawKit

- A developer can add protocol law checking for a custom `Equatable` type in under 5 minutes
- Protocol law violations produce failure messages that identify the specific violated protocol law and provide a reproducible counterexample
- The protocol law library compiles and passes CI on Linux, macOS, and Windows

### PropertyLawMacro

- The discovery CLI correctly identifies conformances in a real-world Swift module with less than 5% false positive suggestions
- Generated test stubs compile without modification for types with derivable generators
- Property contradiction detection catches the idempotent/involutive case and analogous patterns

-----

## 9. Open Questions

1. **Naming**: `SwiftPropertyLaws` / `PropertyLawKit` / `PropertyLawMacro` are working names. Should this be a single package with multiple targets or two separate repositories?
2. **Generator convention**: Should `checkEquatablePropertyLaws` require an explicit `Gen<T>` argument, or attempt `.derived` by default with an explicit override path?
3. **Conformance scope**: Should protocol law checking extend to common third-party protocols (e.g. `Identifiable`, custom algebraic structures) in a separate community-contributed target?
4. **Macro vs. plugin**: Could the discovery functionality be better served as a Swift package plugin (build-time) rather than a macro (compile-time)? Plugins have better file system access for whole-module scanning.
5. **Relationship to swift-testing**: Should `@PropertyLawSuite` be a custom `Suite` trait rather than a standalone macro, to integrate more naturally with Swift Testing’s trait system?

-----

## 10. References

- [swift-property-based](https://github.com/x-sheep/swift-property-based) — primary backend target
- [SwiftQC](https://github.com/Aristide021/SwiftQC) — alternative backend
- [SwiftCheck](https://github.com/typelift/SwiftCheck) — prior art, now dormant
- [QuickCheck](https://hackage.haskell.org/package/QuickCheck) — Haskell reference implementation
- [Hedgehog](https://hackage.haskell.org/package/hedgehog) — state machine testing reference
- [EvoSuite](https://www.evosuite.org) — Java property inference inspiration
- [Daikon](https://plse.cs.washington.edu/daikon/) — runtime invariant inference reference
- Swift Evolution [SE-0185](https://github.com/apple/swift-evolution/blob/main/proposals/0185-synthesize-equatable-hashable.md) — synthesized protocol conformances