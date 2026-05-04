/// A `Semigroup` with a two-sided identity element.
///
/// Conformance asserts that for all values `a` of `Self`,
/// `combine(.identity, a) == a == combine(a, .identity)`. The kit verifies
/// both sides via `checkMonoidPropertyLaws(...)`; the conformance itself
/// declares the identity element alongside the inherited `combine`.
///
/// ## Refines `Semigroup`
///
/// All of `Semigroup`'s laws apply. The kit's inheritance machinery
/// auto-recurses Semigroup's law when checking a Monoid conformance under
/// the default `laws: .all`; pass `.ownOnly` to skip the inherited check.
///
/// ## Conformance shape
///
/// ```swift
/// struct Counter: Monoid, Equatable {
///     var count: Int
///     static let identity = Counter(count: 0)
///     static func combine(_ lhs: Counter, _ rhs: Counter) -> Counter {
///         Counter(count: lhs.count + rhs.count)
///     }
/// }
/// ```
///
/// `Equatable` is required to *check* the laws but not to *declare* the
/// conformance — `Monoid` itself doesn't refine `Equatable`. Same posture
/// as `Semigroup`.
///
/// ## Naming choice
///
/// `identity` rather than `empty` (overlaps with collection emptiness) or
/// `zero` (overlaps with `AdditiveArithmetic.zero` and most monoids aren't
/// additive). When SwiftInferProperties' RefactorBridge writes a
/// conformance for a type whose existing identity has a different name,
/// it bridges via a one-line static aliasing in the extension body.
public protocol Monoid: Semigroup {
    /// The two-sided identity element. Must satisfy
    /// `combine(.identity, a) == a == combine(a, .identity)` for every
    /// `a` of `Self`.
    static var identity: Self { get }
}
