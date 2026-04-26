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

## How to re-run

```bash
Validation/run.sh <path-to-package> <target-name>
# e.g.
Validation/run.sh ~/xcode_projects/swift-argument-parser ArgumentParser
Validation/run.sh ~/xcode_projects/Hummingbird Hummingbird
```

Output lands in `Validation/results/<TargetName>.{generated.swift,summary.txt}`.
