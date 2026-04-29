# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository state

**ProtocolLawKit M1–M5 + v1.1 M1 shipped. ProtoLawMacro M1–M5 shipped. Validation Pass 1–3 shipped. v1.0.0 + v1.1.0 released.** The kit covers Equatable, Hashable, Comparable, Strideable, Codable, IteratorProtocol, Sequence, Collection, SetAlgebra (PRD §4.3 — SetAlgebra now nine laws, expanded from five; see "SetAlgebra symmetric-difference expansion" below; Strideable shipped in v1.1 M1 with four Strict-tier round-trip / identity / self-distance laws — `checkStrideableProtocolLaws` requires an explicit `strideGenerator: Generator<Value.Stride, _>` because Stride is an associated type, and Strideable is on the macro/plugin's "unemittable" list alongside IteratorProtocol because that arg can't be synthesized from inheritance-clause syntax — types declaring `: Strideable` get `checkComparableProtocolLaws` emitted instead, since Strideable refines Comparable in stdlib); the suppression / intentional-violation API (§4.7); the public `PropertyBackend` abstraction (§4.5) with `SwiftPropertyBasedBackend` as the single backend; the M5 confidence-reporting upgrade (replay environment validation, near-miss tracking, opt-in `CoverageClassifier`, formatter rendering); the `@ProtoLawSuite` peer macro (PRD §5.3 Macro Mode); the `swift package protolawcheck discover` Swift Package Plugin (PRD §5.3 Discovery Mode); generator derivation (PRD §5.7) for `CaseIterable` enums + `RawRepresentable` enums, with a shared `DerivationStrategist` keeping the macro and the plugin in lock-step; the M4 Advisory layer's missing-conformance suggester (PRD §5.4) — opt-in via `--advisory`, HIGH-confidence syntactic detectors for `Equatable`, `Hashable`, `Comparable`, `Codable`, output to stderr only so the regeneration-as-diff guarantee on the generated test file is preserved; and the M5 Advisory layer's cross-function round-trip discovery (PRD §5.5) — same `--advisory` flag, syntactic pair detector matching curated naming pairs (encode/decode, serialize/deserialize, push/pop, etc.) and signature inversion across same-type member functions plus module-level free functions, plus a `@Discoverable(group:)` peer macro that promotes pairs sharing an explicit group to HIGH confidence even without a curated naming match.

**SetAlgebra symmetric-difference expansion.** PRD §4.3 SetAlgebra originally listed five Strict-tier laws (`unionIdempotence`, `intersectionIdempotence`, `unionCommutativity`, `intersectionCommutativity`, `emptyIdentity`). None of them exercise `symmetricDifference`. The Pass 3 git-archaeology against `swift-collections@35349601` ("Typo: symmetric difference should be the xor, not intersection") surfaced this gap. Four `symmetricDifference*` laws — `symmetricDifferenceSelfIsEmpty`, `symmetricDifferenceEmptyIdentity`, `symmetricDifferenceCommutativity`, `symmetricDifferenceDefinition` — now ship in `SetAlgebraLaws.swift` with a `BuggySymmetricDifference` planted-bug guard.

**§8 calibrated to reality in PRD v0.3.** v0.2's "catch a real semantic conformance bug in 5+ popular packages before 1.0" gate proved empirically uncloseable. Pass 3 (`Validation/Tests/ValidationPass3Tests`) pinned `swift-collections` to the buggy parent SHA `8e5e4a8f` and ran the kit against `TreeSet<Int>`; every law passed, because `_Bitmap.symmetricDifference` is dead code at that SHA (`TreeSet.symmetricDifference` dispatches through `_HashNode._symmetricDifference_slow*`, never invoking the bitmap method — Apple's commit was correct fix-on-sight cleanup of dead code, not a behavioral fix). Across four full-history Apple/SSWG/community Swift packages (~5,200 commits surveyed), that was the only candidate fix-commit that survived initial filtering. **PRD v0.3 §8 replaces the bug-catch criterion with a three-pass External validation gate**: Pass 1 (discovery scan over ≥4 packages), Pass 2 (kit composes with ≥1 external SwiftPM dep), Pass 3 (git-archaeology with results documented in `Validation/FINDINGS.md` regardless of outcome). All three are shipped. See PRD §8 Appendix A for the v0.2 → v0.3 changelog.

**Single-backend by design.** PRD §4.8 originally proposed shipping `SwiftQCBackend` as a second backend alongside `swift-property-based`. v1 deliberately drops that — `swift-property-based` is the single best-of-breed implementation, the abstraction stays public so a future second backend can drop in without protocol changes, but the kit doesn't chase parity for its own sake. (SwiftQC v1.0.0 also doesn't compile on Swift 6.3 anyway — `Range+Arbitrary.swift:105` captures `var val1`/`val2` in a `@Sendable` closure — but the choice to ship single-backend is the deliberate product decision, not a workaround.)

**Macro shape pivot from PRD §5.3.** The PRD's `@ProtoLawSuite(types: [Foo.self, Bar.self])`-on-a-test-suite form can't be implemented as a Swift macro: macro implementations see only their decoratee's syntax, not the surrounding file. M1 ships a peer-macro-on-the-type variant; the multi-type cross-file form lives on the M2 plugin side.

**Discovery plugin (M2).** `swift package protolawcheck discover --target <name>` walks every `.swift` file in the named target, aggregates type declarations + extensions across files, applies the §4.3 most-specific dedupe, and emits a `*.generated.swift` test file. Output is fully deterministic — re-running with no source changes produces byte-identical output. Suppression markers (`// proto-law-suppress: <protocol>_<TypeName>`) survive regeneration: the user marks a test as suppressed, the next run preserves the marker and replaces the test body with a comment stub.

The path `/Users/joecursio/xcode_projects/SwiftProtocolLaws` and `/Users/joecursio/xcode_projects/swiftProtocolLaws` resolve to the same directory (macOS case-insensitive HFS+/APFS). They are not two checkouts.

## What this repo is

A design / proposal repository for two related Swift packages:

- **SwiftProtocolLaws** — `ProtocolLawKit` (a runtime library of property-based protocol law checks for Swift Standard Library protocols: `Equatable`, `Hashable`, `Comparable`, `Codable`, `Collection`, `SetAlgebra`) plus `ProtoLawMacro` (a SwiftSyntax-based layer that detects conformances and generates `checkXxxProtocolLaws(...)` test stubs). See `docs/SwiftProtocolLaws PRD.md`.
- **SwiftInferProperties** — downstream of SwiftProtocolLaws. `TemplateEngine` (signature-pattern matcher that proposes round-trip / idempotence / commutativity / etc. tests) and `TestLifter` (lifts existing XCTest / Swift Testing methods into generalized property tests). See `docs/SwiftInferProperties PRD.md`.

The intended dependency direction is one-way: `SwiftInferProperties → SwiftProtocolLaws (PropertyBackend) → swift-property-based`. v1 ships `swift-property-based` as the single backend; see the "Single-backend by design" note above.

## Where to look

| Question | File |
|---|---|
| Product scope, milestones, success criteria | `docs/SwiftProtocolLaws PRD.md` (v0.3, current), `docs/SwiftInferProperties PRD.md` |
| What v0.3 changed vs v0.2 | Appendix A of the current PRD (§8 calibration + SetAlgebra symmetric-difference expansion) |
| What v0.2 changed vs the original proposal | Appendix B of the current PRD; `docs/SwiftProtocolLaws PRD v0.1.md` is the preserved original |
| Which protocols and what protocol laws each one carries (with strictness tiers) | `docs/Swift Standard Library Protocols.md` (reference) and §4.3 of the SwiftProtocolLaws PRD |
| External pushback that drove v0.2 | `docs/ChatGPT critique.md`, `docs/Copilot critique.md`, `docs/Gemini critique.md` |

The critiques drove the v0.1 → v0.2 revision. v0.2 closes most of what they raised; the section below is now load-bearing context, not a punch list of unresolved tensions.

## Design decisions baked into v0.2

A future Claude implementing the package should follow these decisions rather than re-litigate them. They live in the PRD; this is a quick map.

- **Strictness tiers per protocol law.** Strict / Conventional / Heuristic. Conventional and Heuristic violations do not fail tests by default — only when the caller passes `.strict`. PRD §4.2.
- **Generator derivation is opt-in and visible.** `using:` requires an explicit `Gen<T>` by default; `.derived` walks a priority list (CaseIterable → memberwise-Arbitrary → RawRepresentable → Codable round-trip), and the *only* fallback when nothing matches is a non-compiling `.todo` stub. Silent green tests from weak generators are the failure mode being prevented. PRD §5.7.
- **Layered ProtoLawMacro scope.** Core = conformance → test stubs (always on). Advisory = missing-conformance suggestions, cross-function discovery (off by default). Experimental = pattern warnings, Codable-derived generators (off by default). Don't put new features in Core without justification. PRD §5.2.
- **Discovery is a Swift Package Plugin, not a macro.** The per-suite trait/macro is a macro; whole-module discovery is a build-tool plugin because macros can't read sibling files. PRD §9 Decision 4.
- **`@ProtoLawSuite` is a Swift Testing custom Trait** (`@Test(.protocolLaws(...))`). Reuse the runner's reporting / filtering / parallelization rather than reinventing them. The freestanding `@ProtoLawSuite` macro form remains for non-Swift-Testing callers. PRD §9 Decision 5.
- **`PropertyBackend` is public as of M4, single-backend by design.** Closure-shaped abstraction (`sample: (inout Xoshiro) -> Input`, `property: @Sendable (Input) async throws -> Bool`) per the M4 backend-survey seam recommendation. `SwiftPropertyBasedBackend` is the only backend v1 ships; the abstraction stays so future alternatives drop in without protocol changes.
- **Pattern warnings, not contradiction detection.** §5.6 is a curated, named-pattern list (idempotent+involutive ⇒ identity, etc.). It does not aspire to soundness/completeness; new patterns require maintainer commits, not graph reasoning. PRD §5.6.
- **Trial budget is part of the API.** `.sanity` (100) / `.standard` (1,000, default) / `.exhaustive` (10,000) / `.custom`. CI cost is a real constraint. PRD §4.4.
- **Suppression is first-class.** Per-type, per-law, intentional-violation, and custom-equivalence APIs exist (PRD §4.7). This is the adoption-failure escape hatch.
- **Validation gate before 1.0.** Must catch a real semantic bug in 5+ popular open-source Swift packages. PRD §8. Don't ship 1.0 without that.
- **Framework self-test gate (every CI run).** Planted-bug suite asserts the framework catches every Strict violation; ProtocolLawKit eats its own dog food. PRD §8.
- **Inheritance is implicit by default.** `checkHashableProtocolLaws` runs Equatable's laws automatically; `checkComparable` runs Equatable's; `checkCollection` runs Sequence's and IteratorProtocol's. Property tests are too slow to make "remember to chain inherited suites" the caller's responsibility — forgetting is a silent way to miss real bugs. Opt-out via `laws: .ownOnly`. The Discovery plugin emits the most-specific call per type (one `checkComparable`, not separate `checkEquatable` + `checkComparable`) so generated tests don't double-run inherited laws. PRD §4.3.
- **Coverage scope is tiered, not exhaustive.** v1 = the 8 protocols in §4.3 (incl. `Sequence`/`IteratorProtocol`). v1.1 candidates and permanently-out-of-scope protocols are enumerated in §4.3 Coverage Scope, cross-referenced to `docs/Swift Standard Library Protocols.md`. Don't quietly add new protocols to Core; add them to Coverage Scope first.
- **Generic conformances need explicit bindings.** `@LawGenerator(bindings: [Container<Int>.self, Container<String>.self])` — the plugin does not enumerate the unbounded generic instantiation space. PRD §4.4 Generic Conformances.
- **`Codable.partial(fields:)` uses `PartialKeyPath`, not strings.** Type-safe, refactor-safe. PRD §4.3.
- **Replay seeds carry an environment fingerprint.** Swift version + backend version + generator-schema hash. A stale seed fails loudly instead of silently replaying as a different test. PRD §4.6.
- **Near-miss is defined per-protocol.** Don't invent a global definition; consult the §4.6 near-miss table. Backends that can't track near-misses report `nearMisses: nil`, not `[]`.
- **Generator registry is an actor.** Concurrency-safe under Swift 6 strict concurrency; not `static var`. PRD §4.5 Actor-Isolated Types.

## Build & test

- `swift package clean && swift test` (per the global `~/CLAUDE.md`) on session start. The full suite runs in well under a second.
- SwiftLint config lives at `.swiftlint.yml`; `swiftlint lint --quiet` should be silent.
- `ProtocolLawKit` and `ProtoLawMacro` are the shipped product targets (M1–M5 and M1–M3 respectively). `SwiftInferProperties` is forward-looking proposal-status — no code yet, see `docs/SwiftInferProperties PRD.md`.
