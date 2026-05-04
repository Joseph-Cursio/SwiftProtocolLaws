/// A `CommutativeMonoid` whose `combine` operation is idempotent.
///
/// Conformance asserts that, for all values `a` of `Self`,
/// `combine(a, a) == a` in addition to the inherited CommutativeMonoid
/// laws (associativity from `Semigroup`, two-sided identity from `Monoid`,
/// commutativity from `CommutativeMonoid`). The kit verifies the new law
/// via `checkSemilatticePropertyLaws(...)`; the conformance itself adds
/// no requirements beyond `CommutativeMonoid`.
///
/// Mathematically, a Semilattice is a CommutativeMonoid where every
/// element absorbs into itself under `combine`. Bounded join-semilattices
/// (like `(Set<T>, ∪, ∅)` or `(Int, max, .min)`) are the most common
/// shape in everyday Swift code; bounded meet-semilattices (like
/// `(Int, min, .max)` or `(Bool, &&, true)`) are equally valid and use
/// the same `Semilattice` conformance.
///
/// ## Refines `CommutativeMonoid`
///
/// All of `CommutativeMonoid`'s, `Monoid`'s, and `Semigroup`'s laws
/// apply. The kit's inheritance machinery auto-recurses the chain when
/// checking a Semilattice conformance under the default `laws: .all`;
/// pass `.ownOnly` to skip the inherited checks.
///
/// ## Conformance shape
///
/// ```swift
/// struct MaxInt: Semilattice, Equatable {
///     let value: Int
///     static let identity = MaxInt(value: .min)
///     static func combine(_ lhs: MaxInt, _ rhs: MaxInt) -> MaxInt {
///         MaxInt(value: max(lhs.value, rhs.value))
///     }
/// }
/// ```
///
/// `Equatable` is required to *check* the laws but not to *declare* the
/// conformance — same posture as `Semigroup`, `Monoid`, and
/// `CommutativeMonoid`.
///
/// ## Why kit-defined
///
/// Stdlib has `SetAlgebra` (covers set-shaped types with union /
/// intersection / containment) but not a general Semilattice. v1.9 adds
/// it for types whose `combine` is idempotent under a name other than
/// `union` / `intersect` (e.g., max-heap-shaped reductions, log-merge
/// types, bloom-filter unions). SwiftInferProperties' M8 RefactorBridge
/// promotes CommutativeMonoid claims to Semilattice when idempotence
/// also fires, narrowing the structural claim per PRD v0.4 §5.4. The
/// secondary `SetAlgebra` Option B applies when the user's type also
/// has set-named ops (mirrors PRD §5.4 row 2's primary-kit + secondary-
/// stdlib pattern).
public protocol Semilattice: CommutativeMonoid {}
