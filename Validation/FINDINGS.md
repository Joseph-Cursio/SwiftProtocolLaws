# Validation findings (PRD §8 — first pass)

PRD §8 calls for catching at least one real semantic conformance bug in 5+ popular open-source Swift packages before 1.0. This document records the first-pass survey: scan-only validation that exercises the discovery plugin's whole-module pipeline against real-world Swift codebases and identifies which types would be law-checked if those projects adopted the kit.

## What this pass covers

| Package | Source files scanned | Types detected | `@Suite struct`s emitted |
|---|---|---|---|
| `swift-argument-parser` (Apple) | 49 | 99 | 15 |
| `Hummingbird` (community Swift server framework) | 74 | 100 | 10 |
| `swift-aws-lambda-runtime` (Apple/SSWG) | 43 | 35 | 8 |
| `Sitrep` (small utility) | 1 file (SitrepCore) | 18 | 2 |

Generated files live in `Validation/results/<TargetName>.generated.swift`; per-target summaries (types that would need a manual `gen()` method) live in `Validation/results/<TargetName>.summary.txt`.

## What this pass *doesn't* do

This is **scan-only** validation. It proves:

1. The discovery plugin handles real-world Swift codebases without crashing or producing malformed output.
2. The most-specific-conformance dedupe works against codebases the kit's authors didn't write.
3. The `.todo` telemetry surfaces every type that would need a manual `gen()`.
4. Output is sensible — emitted `@Test` shapes look like what a maintainer would write themselves.

It does **not** run the kit's `checkXxxProtocolLaws` against these packages. Doing so requires per-package work that's outside the scope of this first pass:

1. Adding `SwiftProtocolLaws` + `swift-property-based` as dependencies to each target package's manifest.
2. Writing a `gen()` static method per surveyed type (M3 derivation only auto-handles `CaseIterable` enums and `RawRepresentable` enums with stdlib raw types — those are the minority).
3. Compiling + running the generated tests under each backend's trial budget.

That's the next-pass deliverable when the validation gate is the active priority.

## What surfaced — sample types worth following up

### `swift-argument-parser`

Notable `Hashable` conformers (the most-specific dedupe shows Hashable subsuming Equatable):

- `ExitCode` — the public exit-code wrapper. Custom `Hashable` would be the most likely place for a hash/equality-consistency bug.
- `CompletionShell` — completion-shell selector enum. `Hashable` likely synthesized.
- `Name`, `InputKey`, `InputOrigin` — internal name-tracking types. Custom `Hashable` plausible.
- `FlagExclusivity`, `FlagInversion`, `ArgumentVisibility` — likely `RawRepresentable` enums; M3 would auto-derive their generators.

### `Hummingbird`

Notable `Codable` conformers (round-trip the most likely failure-mode in server-side code):

- `MediaType` — HTTP MIME-type model. Codable + custom (de)serialization heuristics are a typical place for round-trip drift.
- `URLEncodedFormNode`, `URLEncodedFormError` — form-decoding internals. Custom Codable common in URL-encoded form handling.
- `RouterPath`, `RouterValidationError` — routing AST. Custom equality plausible.

### `swift-aws-lambda-runtime`

Server-side Swift; less-explored Codable surface than Hummingbird. Eight emitted suites suggest most types are internal-state / actor-shaped and don't expose stdlib conformances directly.

### `Sitrep`

Small target; only `Configuration` and `Report` surfaced. Both look like data-class wrappers — a quick hand-survey turned up nothing surprising.

## Honest assessment

After scanning four real-world Swift packages with combined ~209 source files and ~252 declared types, the discovery plugin emitted ~35 `@Suite struct`s' worth of law-check scaffolding. None of the scaffolding looks malformed; the dedupe rules behaved as documented; provenance comments correctly traced types back to their declaring files.

**No conformance bugs were caught in this pass — none were possible to catch, because the kit's checks weren't actually run.** That's the architectural ceiling on scan-only validation, not a comment on the surveyed packages. Apple's `swift-argument-parser` and well-tested community packages like `Hummingbird` are precisely the case where finding a real bug would be unexpected — they're tested heavily, including with property-based approaches in some cases.

The PRD §8 1.0 gate ("must catch a real semantic conformance bug in 5+ popular Swift packages") remains open. Closing it requires the next-pass work above: actual integration of `ProtocolLawKit` into one or more of these packages' test targets and running the checks at full budget.

## What this pass does justify

- The discovery plugin works on real codebases, not just the kit's own fixtures.
- The most-specific-conformance dedupe is correct against varied real-world type shapes.
- The `.todo` telemetry list is concise enough to be actionable (e.g. ArgumentParser surfaced 99 types, 84 of which would need a manual `gen()` — manageable for a maintainer to triage).
- Generated output is human-readable and would survive code-review without churn.

## How to re-run pass 1 (scan-only)

```bash
Validation/run.sh <path-to-package> <target-name>
# e.g.
Validation/run.sh ~/xcode_projects/swift-argument-parser ArgumentParser
Validation/run.sh ~/xcode_projects/Hummingbird Hummingbird
```

Output lands in `Validation/results/<TargetName>.{generated.swift,summary.txt}`.

## Pass 2: actual law checks against an external package

`Validation/Package.swift` is a separate SwiftPM package that depends on the parent (via local path) and on `swift-argument-parser` (via remote). It runs the kit's `checkXxxProtocolLaws` against public types from ArgumentParser. Kept separate so the external dep doesn't leak into the kit's main manifest — consumers of `SwiftProtocolLaws` never see ArgumentParser.

```bash
cd Validation && swift test
```

### Targets exercised

| Type | Source | Law checked | Trial budget | Result |
|---|---|---|---|---|
| `ArgumentParser.ExitCode` | wrapper around `Int32`, `RawRepresentable + Hashable` | `Hashable` (Equatable + equality consistency + stability + distribution) | `.standard` (1,000) | passed |
| `ArgumentParser.ExitCode` | as above | `RawRepresentable` (round-trip) — added 2026-04-29 | `.standard` (1,000) | passed |
| `ArgumentParser.ArgumentVisibility` | three-static-instance struct, `Hashable` | `Hashable` (full inherited suite) | `.standard` (1,000) | passed |
| `ArgumentParser.CompletionShell` | closed-set String-backed `RawRepresentable` (zsh/bash/fish) — added 2026-04-29 | `RawRepresentable` (round-trip) | `.standard` (1,000) | passed |

All four conformances satisfy every Strict-tier law the kit checks. The two RawRepresentable checks were added alongside the v1.1 RawRepresentable law shipping; both pass at `.standard` budget against the public surface.

### What pass 2 actually proves

1. **The kit composes cleanly with an external Swift package.** SwiftPM resolves both deps, the test target links against ArgumentParser + ProtocolLawKit, generators reference public ArgumentParser API, and the kit's checks run unmodified against types the kit's authors didn't write.
2. **The pipeline shape works for an adopter.** A maintainer wanting to validate their own types follows the same recipe: separate test package OR test target with both deps, write `gen()`, call `checkXxxProtocolLaws`. The Validation/Package.swift is a worked example.
3. **At least one Strict-tier `Hashable` law check has run end-to-end against external Apple OSS code.** That's a concrete artifact, even though the result is "the laws hold."

### What pass 2 still doesn't do

The PRD §8 1.0 gate ("at least one real semantic conformance bug in 5+ popular Swift packages") remains open in the literal sense — no bug was caught. Closing it requires either:

- Surveying enough types/packages that one eventually surfaces a real bug (statistical play; takes patience because well-tested OSS is mostly clean).
- Targeting types specifically *suspected* of having issues — places where custom equality or Codable round-trip is implemented manually, where the prior-art property test coverage is thin.

For v1's purposes, the validation infrastructure is shipped and a non-trivial slice of it is exercised against real external code. Bug-hunting can happen incrementally as the kit gets adopted.

## Pass 3: git-archaeology + retroactive validation

Pass 2 confirmed the kit composes with external code but did not catch a real bug. Pass 3 inverts the search: instead of running the kit forward against current code and hoping a bug surfaces, scan the *git history* of popular Swift packages for fix commits that look like protocol-law violations, then check out the pre-fix SHA and try to retroactively catch the bug.

### Survey scope

Searched four full-history Swift packages — combined ~5,200 commits:

| Package | Commits | Conformance fixes worth inspecting |
|---|---|---|
| `swift-argument-parser` | 515 | 0 (synthesized + parser/decoder bugs only) |
| `swift-aws-lambda-runtime` | 434 | 0 (correct on arrival; no patches) |
| `swift-collections` | 1,873 | 1 candidate (`35349601`) |
| `swift-nio` | 2,605 | 0 (internal types or non-law methods) |
| `hummingbird` | 973 | 0 (Codable surface is small) |

Search strategy: `git log --grep="hash|equ|codable|encode|decode|comparable|round.?trip|symmet|transit|consist"`, then diff inspection on every promising candidate. Rejection categories that came up repeatedly:

- *Adding* missing conformance (not a bug fix)
- Bugs in `internal`/`fileprivate` types (no public surface to test)
- Bugs in custom `KeyedDecodingContainerProtocol` implementations (decoder internals, not a value type's `init(from:)`/`encode(to:)`)
- Pure refactors that preserved semantics
- Bugs in user-named methods (e.g. `BitSet.isEqualSet(to:)`) that aren't the protocol's `==` / `hash(into:)` / `<` / Codable round-trip

### The candidate: `swift-collections@35349601`

> "Typo: symmetric difference should be the xor, not intersection. Otherwise it is the same as the intersection."

```diff
- internal func symmetricDifference(_ other: Self) -> Self {
-   Self(_value: _value & other._value)
- }
+ internal func symmetricDifference(_ other: Self) -> Self {
+   Self(_value: _value ^ other._value)
+ }
```

Apple added a regression test in the same commit:

```swift
let left: TreeSet<Int> = [1, 3]
let right: TreeSet<Int> = [2, 3]
let result = left.symmetricDifference(right)
expectEqualSets(result, [1, 2])
```

This is on a public type (`TreeSet`), the bug is on a SetAlgebra-required method, the description names a real algebraic violation. Worth wiring up.

**Kit-coverage gap discovered along the way.** The kit's original five-law SetAlgebra suite — `unionIdempotence`, `intersectionIdempotence`, `unionCommutativity`, `intersectionCommutativity`, `emptyIdentity` — does not exercise `symmetricDifference` at all. Even with the bug observable, none of those laws would have fired on it. Closing this gap meant adding four `symmetricDifference*` laws to PRD §4.3 SetAlgebra:

- `symmetricDifferenceSelfIsEmpty` — `x △ x == .empty`
- `symmetricDifferenceEmptyIdentity` — `x △ .empty == x`
- `symmetricDifferenceCommutativity` — `x △ y == y △ x`
- `symmetricDifferenceDefinition` — `x △ y == x.union(y).subtracting(x.intersection(y))`

The new laws ship in `SetAlgebraLaws.swift` and are guarded by a `BuggySymmetricDifference` planted bug whose `symmetricDifference` returns the intersection (mirroring the exact pre-fix shape).

### What Pass 3 found

`Validation/Tests/ValidationPass3Tests/SwiftCollectionsRetroactiveTests.swift` pins `swift-collections` to revision `8e5e4a8f` — the parent of `35349601`, where the buggy `_Bitmap.symmetricDifference` is in place. Running the kit there produced an unexpected result: **`TreeSet<Int>` passes every kit law, including all four new `symmetricDifference*` laws.**

Apple's own regression test inputs (`[1,3].symmetricDifference([2,3])`) also produce the *correct* answer `[1,2]` at the buggy SHA — not the intersection `[3]` the bug would suggest.

Tracing the public dispatch:

- `TreeSet.symmetricDifference` calls `_HashNode.symmetricDifference`
- `_HashNode.symmetricDifference` calls `_HashNode._symmetricDifference`
- `_symmetricDifference` calls `_symmetricDifference_slow*`
- The slow-path implementations build the result element-by-element via structural traversal in `_HashNode+Structural symmetricDifference.swift`

`_Bitmap.symmetricDifference` is **never called** from this path. A grep across `Sources/HashTreeCollections/` confirms it has no callers outside its own definition. The buggy method is dead code at this SHA.

Apple's commit was correct fix-on-sight cleanup of a real typo, but the typo was in unreachable code. The "regression test" added in the fix commit guards against future code that might begin calling `_Bitmap.symmetricDifference` — not against an observable user-facing bug.

The Pass 3 test target therefore asserts what's empirically true: at the buggy SHA, the kit reports no violation, faithfully reflecting the public semantics. This is the kit doing its job — *not* false-positiving on dead code.

### What this means for PRD §8

The §8 1.0 gate as written ("must catch a real semantic conformance bug in 5+ popular Swift packages") may be miscalibrated. The empirical evidence:

1. Across four full-history Apple/SSWG/community Swift packages (~5,200 commits), exactly one candidate fix-commit looked plausible.
2. That one candidate, on closer inspection, was a fix to dead code — the bug was never observable through the public API.
3. The kit *correctly* reports no violation at the buggy SHA. There is no false-positive failure mode here.

Combined with the structural reasons Apple-maintained Swift code is mostly clean — heavy reliance on synthesized conformances, hand-written impls landing correct on first commit, scrutiny in code review — the conclusion is that closing §8 against well-tested packages is unlikely *not* because the kit is weak, but because the population of historical kit-detectable bugs in well-tested packages is approximately empty.

**Proposed §8 rewrite (open for discussion, not yet committed):** Replace the bug-catch criterion with the following:

- The kit's planted-bug self-test gate (already required by §8) catches every Strict-tier law violation across all 8 covered protocols. ✓ (currently 26 planted-bug detection tests)
- Pass 1 (scan-only discovery against ≥4 real packages) demonstrates the discovery plugin handles real codebases. ✓
- Pass 2 (actual law checks against ≥1 external package's public types) demonstrates the kit composes with external SwiftPM deps. ✓
- Pass 3 (git-archaeology) documents the search effort and any candidate bugs found, regardless of whether the kit catches them. ✓
- The kit ships v1 honestly: the value prop is *prevention* (catch bugs in new code as it's written), not retroactive *discovery* in already-shipped code.

The current §8 wording was an aspirational stretch goal in PRD v0.2; the Pass 3 evidence is grounds for a v0.3 PRD revision that calibrates §8 to reality.

### How to re-run Pass 3

```bash
cd Validation && swift test --filter SwiftCollectionsRetroactiveTests
```

If `swift-collections` ever gains a public observation path through `_Bitmap.symmetricDifference`, the `treeSetPassesAllLawsAtBuggySHA` test will start failing — re-evaluate at that point.

## Revalidation 2026-04-29 — v1.1 + v1.2 + v1.3 against the same packages

After v1.1 (Strideable, RawRepresentable, LosslessStringConvertible, Identifiable, CaseIterable), v1.2 (BidirectionalCollection, RandomAccessCollection, MutableCollection, RangeReplaceableCollection), and v1.3 (Strategy 3 memberwise-Arbitrary derivation) shipped, Pass 1 was rerun against all four packages. Pass 3 was not rerun — none of the new laws apply to `_Bitmap.symmetricDifference`'s dispatch path; the archaeology result is unchanged.

Cloned package SHAs at rescan time:

| Package | Source pin |
|---|---|
| `swift-argument-parser` | `1.6.1-2-gd075877` (already on disk) |
| `Hummingbird` | `581594a` (HEAD of `main`) |
| `swift-aws-lambda-runtime` | `f3bd0ae` (HEAD of `main`) |
| `Sitrep` | `4.0.0` |

### Suite/test deltas (path-noise filtered)

| Package | Suites before → after | New `@Test` checks emitted | New types deriving `gen()` |
|---|---|---|---|
| `swift-argument-parser` | 15 → **16** | `randomAccessCollection_ArgumentSet`, `rawRepresentable_CompletionShell`, `rawRepresentable_ExitCode` | `GenerateCompletions` |
| `Hummingbird` | 10 → 10 | — | — |
| `swift-aws-lambda-runtime` | 8 → 8 | — | `ErrorResponse`, `Request`, `Response` |
| `Sitrep` (`SitrepCore`) | 2 → 2 | — | — |

Three new emitted law-checks (all in ArgumentParser), four new derived generators (one in ArgumentParser, three in AWSLambdaRuntime). The ArgumentSet `RandomAccessCollection` check transitively re-runs Bidirectional + Collection + Sequence + Iterator — a single new `@Test func` exercises the whole chain.

### Why Hummingbird and SitrepCore yielded zero new checks

The v1.1 round-trip cluster fires on inheritance clauses spelling `: RawRepresentable`, `: Identifiable`, etc. Hummingbird's public surface is dominated by HTTP / routing types whose conformances are `Codable`, `Hashable`, or `Sendable` — none of which the new laws add coverage for. SitrepCore is small (18 types) and similarly doesn't surface the new clauses. This is consistent with §8's broader finding: the population of `:Strideable` / `:RawRepresentable` types on real-world Swift codebases is concentrated in a few enums per package.

### Upstream package churn (separate from law deltas)

- Hummingbird: 74 → 73 source files; `Data` no longer surfaces as a detected type (upstream rename/removal between Pass 1 and revalidation).
- SitrepCore: typename refactoring at `4.0.0` — `SwiftSourceComment/Function/Node/Type` and `VisitedFile` were renamed to `Comment / Function / Node / Type / File`.

Neither churn affected the suite or law-check counts.

### How to re-run the revalidation

```bash
swift build --product ProtoLawDiscoveryTool -c release
Validation/run.sh ~/xcode_projects/swift-argument-parser ArgumentParser
Validation/run.sh ~/xcode_projects/Hummingbird Hummingbird
Validation/run.sh ~/xcode_projects/swift-aws-lambda-runtime AWSLambdaRuntime
Validation/run.sh ~/xcode_projects/Sitrep SitrepCore
git diff Validation/results/
```

## Pass 2 expansion 2026-04-29 — v1.4 stdlib numeric coverage

The original Pass 2 (commit `599c843` and earlier) only ran the kit's laws against types from `swift-argument-parser` (`ExitCode`, `ArgumentVisibility`, `CompletionShell`). The v1.4 cluster shipped a new layer of laws — `AdditiveArithmetic` / `Numeric` / `SignedNumeric` / `BinaryInteger` / `SignedInteger` / `UnsignedInteger` / `FixedWidthInteger` / `FloatingPoint` / `BinaryFloatingPoint` — whose canonical reference implementations are stdlib `Int*` / `UInt*` / `Double` / `Float`. Pass 2 now exercises those reference implementations directly.

`Validation/Tests/ValidationPass2Tests/StdlibNumericLawsTests.swift`:

| Type | Laws checked | Trial budget | Result |
|---|---|---|---|
| `Int32` | `checkFixedWidthIntegerProtocolLaws` (which transitively runs BinaryInteger + Numeric + AdditiveArithmetic) | `.standard` (1,000) | passed |
| `Int32` | `checkSignedIntegerProtocolLaws` (sibling chain to FixedWidthInteger) | `.standard` (1,000) | passed |
| `UInt` | `checkFixedWidthIntegerProtocolLaws` | `.standard` (1,000) | passed |
| `UInt` | `checkUnsignedIntegerProtocolLaws` | `.standard` (1,000) | passed |
| `Double` | `checkBinaryFloatingPointProtocolLaws` (finite-only generator, `allowNaN: false`) | `.standard` (1,000) | passed |
| `Double` | `checkBinaryFloatingPointProtocolLaws` (NaN-injecting generator, `allowNaN: true` — exercises NaN-domain laws) | `.standard` (1,000) | passed |

This is the **first time the kit's own laws run end-to-end against stdlib types** — significant for the §8 closure narrative. Apple's reference implementations satisfy every Strict-tier law the v1.4 cluster checks, including the IEEE-754 NaN-domain laws under `allowNaN: true`. As with the original Pass 2, "no bug found" is the predicted result for the most heavily-tested numeric implementations on the planet, but the assertion is now real rather than asymptotic.

The Pass 2 sub-package's `swift test` now runs 12 tests across 3 suites in ≈ 130 ms.

## Revalidation 2026-04-29 (later) — v1.4 numeric/integer/FloatingPoint cluster

After v1.4 (AdditiveArithmetic, Numeric, SignedNumeric, BinaryInteger, SignedInteger, UnsignedInteger, FixedWidthInteger, FloatingPoint, BinaryFloatingPoint — 9 new protocols, 61 new Strict-tier laws) shipped, Pass 1 was rerun against all four packages with the v1.4 plugin against the same SHAs as the v1.1/v1.2/v1.3 revalidation earlier in the day.

### Result: byte-identical output across all four packages

| Package | Suites before → after | New `@Test` checks emitted |
|---|---|---|
| `swift-argument-parser` | 16 → 16 | — |
| `Hummingbird` | 10 → 10 | — |
| `swift-aws-lambda-runtime` | 8 → 8 | — |
| `Sitrep` (`SitrepCore`) | 2 → 2 | — |

**`git diff Validation/results/` returned empty** — the rescan produced bit-identical output to the committed results from earlier in the day. Zero new emit-able conformances across ~252 declared types in ~209 source files.

### Why this null result was predicted

The plan agent's M5 §6 (`docs/Protocols/v1.4 plan.md`) called this:

> Searching the four packages for inheritance clauses spelling any of the nine new protocols would pick up almost nothing:
>
> - `: AdditiveArithmetic`, `: Numeric`, `: SignedNumeric`, `: BinaryInteger`, `: SignedInteger`, `: UnsignedInteger`, `: FixedWidthInteger` — these are essentially never adopted by app code. They exist to constrain stdlib generic algorithms; the only types that adopt them are stdlib's own `Int`/`UInt` family. Custom-precision integer libraries (Numerics, BigInt) are the rare exceptions.
> - `: FloatingPoint`, `: BinaryFloatingPoint` — same story; only `Float`/`Double`/`Float80`/`Float16` conform.

Confirmed empirically. The v1.4 cluster's value isn't in surfacing new app-code conformers — it's in being *available* when a custom-precision numeric type is written, *and* in giving the kit's own laws something to run against stdlib types directly via the Pass 2 expansion above.

### What this means for the §8 closure narrative

The revalidation reinforces the v0.3 §8 calibration: well-tested code rarely contains kit-detectable bugs in the specific protocols the kit covers. The v1.4 cluster's contribution to PRD §8 is:

1. **Pass 1 scope coverage.** All 18 protocols the kit covers in v1.4.0 are exercised by the discovery plugin. The fact that the plugin emits zero new checks for these packages doesn't mean the plugin is broken — it means the packages don't declare the protocols, which is the predicted state of mainstream Swift code.
2. **Pass 2 stdlib coverage.** Six new tests in `StdlibNumericLawsTests.swift` exercise the v1.4 laws against `Int32` / `UInt` / `Double` at `.standard` budget. All pass. First time the kit's own laws have run against stdlib types via the validation harness — addresses the long-standing gap where Pass 2 only exercised ArgumentParser-specific types.
