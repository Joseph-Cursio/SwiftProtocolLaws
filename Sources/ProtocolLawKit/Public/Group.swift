/// A `Monoid` in which every element has a two-sided inverse.
///
/// Conformance asserts that, for all values `a` of `Self`,
/// `combine(a, inverse(a)) == .identity == combine(inverse(a), a)`, in
/// addition to the inherited Monoid laws (associativity from `Semigroup`,
/// two-sided identity from `Monoid`). The kit verifies both inverse laws
/// via `checkGroupProtocolLaws(...)`.
///
/// ## Refines `Monoid`
///
/// All of `Monoid`'s and `Semigroup`'s laws apply. The kit's inheritance
/// machinery auto-recurses Monoid's laws (and transitively Semigroup's)
/// when checking a Group conformance under the default `laws: .all`;
/// pass `.ownOnly` to skip the inherited checks.
///
/// ## Conformance shape
///
/// ```swift
/// struct AdditiveInt: Group, Equatable {
///     let value: Int
///     static let identity = AdditiveInt(value: 0)
///     static func combine(_ lhs: AdditiveInt, _ rhs: AdditiveInt) -> AdditiveInt {
///         AdditiveInt(value: lhs.value + rhs.value)
///     }
///     static func inverse(_ value: AdditiveInt) -> AdditiveInt {
///         AdditiveInt(value: -value.value)
///     }
/// }
/// ```
///
/// `Equatable` is required to *check* the laws but not to *declare* the
/// conformance — same posture as `Semigroup`, `Monoid`, and `CommutativeMonoid`.
///
/// ## Why kit-defined
///
/// Stdlib has `AdditiveArithmetic` (covers `+ / - / .zero`-shaped
/// commutative groups via implied negation) and `SignedNumeric` (covers
/// negation explicitly), but neither offers a general non-commutative
/// Group conformance path or a verifiable inverse law. v1.9 adds it for
/// types whose inverse is named other than `-` (e.g., permutation groups
/// with `inverted()`, modular-arithmetic groups, finite cyclic groups).
/// SwiftInferProperties' M8 RefactorBridge promotes single-Monoid claims
/// to Group when an inverse witness fires, narrowing the structural claim
/// per PRD v0.4 §5.4.
///
/// ## Naming choice
///
/// `inverse(_:)` rather than `inverted()` (instance method, which would
/// require Swift's `-Self` operator overload) or `negated()` (overlaps
/// with `SignedNumeric.negate()`). Static-method form mirrors
/// `combine(_:_:)` and `identity` so the witness-extraction shape stays
/// uniform.
public protocol Group: Monoid {
    /// The two-sided inverse of `value`. Must satisfy
    /// `combine(value, inverse(value)) == .identity == combine(inverse(value), value)`
    /// for every `value` of `Self`.
    static func inverse(_ value: Self) -> Self
}
