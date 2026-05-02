/// A type with an associative binary `combine` operation.
///
/// Conformance asserts that, for all values `a, b, c` of `Self`,
/// `combine(combine(a, b), c) == combine(a, combine(b, c))`. The kit
/// verifies the law via `checkSemigroupProtocolLaws(...)`; the conformance
/// itself only declares the operation.
///
/// ## Why kit-defined
///
/// Stdlib has no `Semigroup` protocol. `AdditiveArithmetic` covers types
/// with `+ / - / .zero`, but most semigroup-shaped Swift types use names
/// like `merge`, `combine`, `concat`, `union` and don't fit `+`'s
/// arithmetic semantics. v1.8 adds `Semigroup` to give those types a
/// conformance path the kit can verify on every CI run, closing the
/// SwiftInferProperties PRD v0.4 §11 discovery → conformance → law-check
/// loop. See `docs/Protocols/v1.8 plan.md`.
///
/// ## Conformance shape
///
/// ```swift
/// struct Counter: Semigroup, Equatable {
///     var count: Int
///     static func combine(_ lhs: Counter, _ rhs: Counter) -> Counter {
///         Counter(count: lhs.count + rhs.count)
///     }
/// }
/// ```
///
/// `Equatable` is required to *check* the law, not to *declare* the
/// conformance — `Semigroup` itself doesn't refine `Equatable`. Types
/// that don't conform to `Equatable` can still declare `Semigroup`
/// conformance; the law just can't be verified.
///
/// ## Refined by `Monoid`
///
/// `Monoid` adds a `static var identity: Self` requirement. The kit's
/// inheritance machinery auto-recurses Semigroup's law when checking a
/// Monoid conformance.
public protocol Semigroup {
    /// Combine two values into a third. The operation must be
    /// associative: `combine(combine(a, b), c) == combine(a, combine(b, c))`.
    static func combine(_ lhs: Self, _ rhs: Self) -> Self
}
