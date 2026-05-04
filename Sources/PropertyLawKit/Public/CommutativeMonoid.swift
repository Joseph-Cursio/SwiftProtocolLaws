/// A `Monoid` whose `combine` operation is commutative.
///
/// Conformance asserts that, for all values `a, b` of `Self`,
/// `combine(a, b) == combine(b, a)` in addition to the inherited Monoid
/// laws (associativity from `Semigroup`, two-sided identity from `Monoid`).
/// The kit verifies the new law via `checkCommutativeMonoidPropertyLaws(...)`;
/// the conformance itself adds no requirements beyond `Monoid` — the
/// commutativity claim is purely a tier-strict law check.
///
/// ## Refines `Monoid`
///
/// All of `Monoid`'s and `Semigroup`'s laws apply. The kit's inheritance
/// machinery auto-recurses Monoid's laws (and transitively Semigroup's)
/// when checking a CommutativeMonoid conformance under the default
/// `laws: .all`; pass `.ownOnly` to skip the inherited checks.
///
/// ## Conformance shape
///
/// ```swift
/// struct Tally: CommutativeMonoid, Equatable {
///     var count: Int
///     static let identity = Tally(count: 0)
///     static func combine(_ lhs: Tally, _ rhs: Tally) -> Tally {
///         Tally(count: lhs.count + rhs.count)
///     }
/// }
/// ```
///
/// `Equatable` is required to *check* the laws but not to *declare* the
/// conformance — same posture as `Semigroup` and `Monoid`.
///
/// ## Why kit-defined
///
/// Stdlib has `AdditiveArithmetic` (covers commutative `+`-shaped types
/// with `.zero`) but not a general CommutativeMonoid. v1.9 adds it to
/// give counter-shaped, max-shaped, set-union-shaped, and other commutative
/// `combine` operations a verifiable conformance path. SwiftInferProperties'
/// M8 RefactorBridge promotes single-Monoid claims to CommutativeMonoid
/// when commutativity also fires, narrowing the structural claim per
/// PRD v0.4 §5.4.
///
/// ## Refined by `Semilattice`
///
/// `Semilattice` adds `combineIdempotence` (`combine(a, a) == a`). The kit's
/// inheritance machinery auto-recurses CommutativeMonoid's law when checking
/// a Semilattice conformance.
public protocol CommutativeMonoid: Monoid {}
