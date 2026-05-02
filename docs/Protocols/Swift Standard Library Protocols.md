# Swift Standard Library Protocols

A comprehensive reference of all ~54 public protocols in the Swift Standard Library, grouped by category.

-----

## 1. Equality & Comparison

### `Equatable`

- **Requirement:** `static func == (lhs: Self, rhs: Self) -> Bool`
- Types that can be compared for equality. Enables use of `==` and `!=`.

### `Comparable`

- **Inherits:** `Equatable`
- **Requirement:** `static func < (lhs: Self, rhs: Self) -> Bool`
- Types that have a natural ordering. Enables `<`, `>`, `<=`, `>=` and use in `sorted()`.

### `Hashable`

- **Inherits:** `Equatable`
- **Requirement:** `func hash(into hasher: inout Hasher)`
- Types that can be hashed to an integer. Required to be used as `Dictionary` keys or in `Set`.

### `Identifiable`

- **Requirement:** `var id: ID { get }` (where `ID: Hashable`)
- Types with a stable identity. Widely used in SwiftUI `List` and `ForEach`.

-----

## 2. Collections

### `Sequence`

- **Requirement:** `func makeIterator() -> Self.Iterator`
- The most basic protocol for anything you can loop over with `for...in`.

### `IteratorProtocol`

- **Requirement:** `mutating func next() -> Element?`
- Provides values one at a time. Returned by `Sequence.makeIterator()`.

### `Collection`

- **Inherits:** `Sequence`
- **Requirements:** `var startIndex: Index`, `var endIndex: Index`, `subscript(position: Index) -> Element`, `func index(after i: Index) -> Index`
- A sequence you can traverse multiple times with subscript access.

### `BidirectionalCollection`

- **Inherits:** `Collection`
- **Requirement:** `func index(before i: Index) -> Index`
- A collection that can be traversed both forward and backward.

### `RandomAccessCollection`

- **Inherits:** `BidirectionalCollection`
- **Requirement:** O(1) index manipulation (no explicit method beyond `BidirectionalCollection`)
- A collection with efficient random access (like arrays).

### `MutableCollection`

- **Inherits:** `Collection`
- **Requirement:** `subscript(position: Index) -> Element { get set }`
- A collection whose elements can be modified in place.

### `RangeReplaceableCollection`

- **Inherits:** `Collection`
- **Requirements:** `init()`, `mutating func replaceSubrange(_ subrange: Range<Index>, with newElements: C)`
- A collection that supports inserting and removing elements.

### `StringProtocol`

- **Inherits:** `BidirectionalCollection`, `Hashable`, `Comparable`
- **Key properties:** `var utf8: UTF8View`, `var utf16: UTF16View`, `var unicodeScalars: UnicodeScalarView`
- Shared interface for `String` and `Substring`.

### `LazySequenceProtocol`

- **Inherits:** `Sequence`
- **Requirement:** `var elements: Elements { get }`
- A sequence that applies transformations lazily (on demand).

### `LazyCollectionProtocol`

- **Inherits:** `LazySequenceProtocol`, `Collection`
- The collection counterpart to `LazySequenceProtocol`.

### `SetAlgebra`

- **Inherits:** nothing in stdlib (every adopting type is also `Equatable` in practice; the comparison-based laws in `ProtocolLawKit` require it).
- **Requirements:** `init()`, `func contains(_ member: Element) -> Bool`, `func union(_ other: Self) -> Self`, `func intersection(_ other: Self) -> Self`, `func symmetricDifference(_ other: Self) -> Self`, `mutating func formUnion(_ other: Self)`, `mutating func formIntersection(_ other: Self)`, `mutating func formSymmetricDifference(_ other: Self)`, `mutating func insert(_ newMember: Element) -> (inserted: Bool, memberAfterInsert: Element)`, `mutating func remove(_ member: Element) -> Element?`, `mutating func update(with newMember: Element) -> Element?`.
- A type representing a mathematical set, with union, intersection, and symmetric-difference operations. Adopters: `Set`, `OptionSet`, `IndexSet`, `CharacterSet`, plus third-party types like `OrderedSet`, `TreeSet`, `BitSet`. Note: SetAlgebra is filed under Apple's "Collections" documentation topic but does *not* inherit from `Collection` — `Set` adopts both protocols separately. ProtocolLawKit covers nine SetAlgebra laws (see PRD §4.3 SetAlgebra), including four `symmetricDifference*` laws that close the algebraic identity for the operation.

-----

## 3. Numeric Protocols

### `Numeric`

- **Inherits:** `Equatable`, `ExpressibleByIntegerLiteral`
- **Requirements:** `+`, `-`, `*`, `init(exactly:)`
- Base protocol for all numeric types.

### `SignedNumeric`

- **Inherits:** `Numeric`
- **Requirement:** `mutating func negate()`
- Numeric types that can be negative.

### `AdditiveArithmetic`

- **Inherits:** `Equatable`
- **Requirements:** `static var zero: Self`, `+`, `-`
- Types supporting addition and subtraction.

### `BinaryInteger`

- **Inherits:** `Numeric`, `Hashable`, `CustomStringConvertible`, `Strideable`
- **Requirements:** `init<T: BinaryInteger>(_ source: T)`, bitwise operators (`&`, `|`, `^`, `~`, `<<`, `>>`)
- Base protocol for all integer types (`Int`, `UInt`, etc.).

### `SignedInteger`

- **Inherits:** `BinaryInteger`, `SignedNumeric`
- Signed integer types (`Int`, `Int8`, `Int16`, `Int32`, `Int64`).

### `UnsignedInteger`

- **Inherits:** `BinaryInteger`
- Unsigned integer types (`UInt`, `UInt8`, `UInt16`, `UInt32`, `UInt64`).

### `FixedWidthInteger`

- **Inherits:** `BinaryInteger`
- **Key properties/requirements:** `static var bitWidth: Int`, `static var max: Self`, `static var min: Self`, overflow operators (`&+`, `&-`, `&*`), `nonzeroBitCount`, `leadingZeroBitCount`
- Integer types with a fixed bit width.

### `FloatingPoint`

- **Inherits:** `SignedNumeric`, `Strideable`, `Hashable`
- **Key properties:** `var isNaN: Bool`, `var isInfinite: Bool`, `var isFinite: Bool`, `var isZero: Bool`, `var sign: FloatingPointSign`, `var exponent: Exponent`, `var significand: Self`
- **Key requirements:** `static var infinity: Self`, `static var nan: Self`, `static var pi: Self`, `func squareRoot() -> Self`, `mutating func round(_ rule: FloatingPointRoundingRule)`
- Base for all floating-point types.

### `BinaryFloatingPoint`

- **Inherits:** `FloatingPoint`
- **Requirements:** `static var exponentBitCount: Int`, `static var significandBitCount: Int`
- Floating-point types using binary encoding (`Float`, `Double`, `Float80`).

### `Strideable`

- **Inherits:** `Comparable`
- **Requirements:** `func distance(to other: Self) -> Stride`, `func advanced(by n: Stride) -> Self`
- Types that can be stepped through in a `for` loop with `stride(from:to:by:)`.

-----

## 4. Encoding & Decoding

### `Encodable`

- **Requirement:** `func encode(to encoder: Encoder) throws`
- Types that can encode themselves (e.g., to JSON).

### `Decodable`

- **Requirement:** `init(from decoder: Decoder) throws`
- Types that can decode themselves from external data.

### `Codable`

- **Inherits:** `Encodable`, `Decodable`
- Typealias combining both. The standard way to support JSON/Plist serialization.

### `Encoder`

- **Key requirements:** `var codingPath: [CodingKey]`, `var userInfo: [CodingUserInfoKey: Any]`, container methods (`container(keyedBy:)`, `unkeyedContainer()`, `singleValueContainer()`)

### `Decoder`

- **Key requirements:** `var codingPath: [CodingKey]`, `var userInfo: [CodingUserInfoKey: Any]`, container methods

### `CodingKey`

- **Requirements:** `var stringValue: String`, `var intValue: Int?`, `init?(stringValue:)`, `init?(intValue:)`
- Keys used in encoding/decoding keyed containers.

-----

## 5. String Representation

### `CustomStringConvertible`

- **Requirement:** `var description: String { get }`
- Provides a human-readable string via `String(describing:)` and print.

### `CustomDebugStringConvertible`

- **Requirement:** `var debugDescription: String { get }`
- Provides a debug-friendly string via `String(reflecting:)`.

### `LosslessStringConvertible`

- **Inherits:** `CustomStringConvertible`
- **Requirement:** `init?(_ description: String)`
- Types that can be round-tripped through a string without information loss.

### `TextOutputStreamable`

- **Requirement:** `func write<Target: TextOutputStream>(to target: inout Target)`
- Types that can write themselves to a text stream.

### `TextOutputStream`

- **Requirement:** `mutating func write(_ string: String)`
- A type that accepts strings written to it (e.g., a custom output buffer).

-----

## 6. Raw Value Representation

### `RawRepresentable`

- **Requirements:** `associatedtype RawValue`, `var rawValue: RawValue { get }`, `init?(rawValue: RawValue)`
- Types (especially enums) that have an underlying raw value representation.

-----

## 7. Memory & Reference

### `AnyObject`

- Protocol to which all class types implicitly conform.
- Used to constrain generics to reference (class) types.

### `AnyClass`

- **Inherits:** `AnyObject`
- The protocol for all metatypes.

### `Sendable`

- Marks types that are safe to use in concurrent code (across actor boundaries). No required methods.

### `Error`

- **Requirement:** None required (beyond conformance)
- Types that can be thrown and caught as errors. Commonly combined with `LocalizedError`.

### `LocalizedError`

- **Inherits:** `Error`
- **Optional properties:** `var errorDescription: String?`, `var failureReason: String?`, `var recoverySuggestion: String?`, `var helpAnchor: String?`

-----

## 8. Literals (ExpressibleBy…)

These protocols let custom types be initialized from literal syntax.

|Protocol                                     |Requirement                            |Literal Type         |
|---------------------------------------------|---------------------------------------|---------------------|
|`ExpressibleByIntegerLiteral`                |`init(integerLiteral:)`                |`42`                 |
|`ExpressibleByFloatLiteral`                  |`init(floatLiteral:)`                  |`3.14`               |
|`ExpressibleByBooleanLiteral`                |`init(booleanLiteral:)`                |`true`               |
|`ExpressibleByStringLiteral`                 |`init(stringLiteral:)`                 |`"hello"`            |
|`ExpressibleByStringInterpolation`           |`init(stringInterpolation:)`           |`"Hello, \(name)"`   |
|`ExpressibleByNilLiteral`                    |`init(nilLiteral:)`                    |`nil`                |
|`ExpressibleByArrayLiteral`                  |`init(arrayLiteral:)`                  |`[1, 2, 3]`          |
|`ExpressibleByDictionaryLiteral`             |`init(dictionaryLiteral:)`             |`["a": 1]`           |
|`ExpressibleByUnicodeScalarLiteral`          |`init(unicodeScalarLiteral:)`          |single Unicode scalar|
|`ExpressibleByExtendedGraphemeClusterLiteral`|`init(extendedGraphemeClusterLiteral:)`|single character     |

-----

## 9. Optionals & Result

### `OptionalProtocol` *(internal)*

- Internal to the standard library; `Optional<Wrapped>` conforms implicitly.

-----

## 10. Miscellaneous

### `Sendable`

- Marks types safe for concurrent use. No method requirements.

### `CustomReflectable`

- **Requirement:** `var customMirror: Mirror { get }`
- Types that provide a custom reflection (used by `Mirror` for introspection).

### `MirrorPath`

- Identifies a particular stored property in a `Mirror` via string or integer subscripts.

### `Hashable` *(see Equality section)*

### `CVarArg`

- Types that can be passed as C variadic arguments. No user-facing requirements.

### `RandomNumberGenerator`

- **Requirement:** `mutating func next() -> UInt64`
- Custom random number generators used with `random(in:using:)` APIs.

-----

## Summary by Category

|Category                 |Count  |
|-------------------------|-------|
|Equality & Comparison    |4      |
|Collections              |10     |
|Numeric                  |10     |
|Encoding & Decoding      |6      |
|String Representation    |5      |
|Raw Value Representation |1      |
|Memory & Reference       |5      |
|Literals (ExpressibleBy…)|10     |
|Miscellaneous            |4      |
|**Total**                |**~54**|

-----

*Based on the Swift Standard Library as of Swift 6.x. The exact count can vary slightly across Swift versions as protocols are added, renamed, or deprecated.*

-----

## Kit-defined Protocols

ProtocolLawKit also defines a small set of protocols where the Swift Standard Library leaves a useful gap. These are kit-owned (not stdlib), shipped from `import ProtocolLawKit`, and verified by the kit's discovery plugin under the same `KnownProtocol`-driven dispatch as the stdlib protocols above.

### `Semigroup` *(v1.8)*

- **Inherits:** nothing
- **Requirement:** `static func combine(_ lhs: Self, _ rhs: Self) -> Self`
- A type with an associative binary `combine` operation. Stdlib has no Semigroup protocol; `AdditiveArithmetic` requires `+` / `-` / `zero` and doesn't fit the common merge-shape Swift case (types with `merge` / `combine` / `concat` / `union` operations that aren't arithmetic-`+`-shaped). Adopters that already conform to `AdditiveArithmetic` can also conform to Semigroup if the kit-side `combine` semantics align — the two are independent.

### `Monoid` *(v1.8)*

- **Inherits:** `Semigroup`
- **Requirement:** `static var identity: Self { get }`
- A `Semigroup` with a two-sided identity element. The `identity` name is chosen over `empty` / `zero` to avoid overlap with `RangeReplaceableCollection.init()` and `AdditiveArithmetic.zero`. SwiftInferProperties' RefactorBridge bridges user-named identities (`.empty`, `.zero`, `.none`, `.default`) to the canonical `.identity` via a one-line static aliasing in the conformance writeout.

### `CommutativeMonoid` *(v1.9)*

- **Inherits:** `Monoid`
- **Requirement:** none beyond Monoid — marker protocol
- A `Monoid` whose `combine` operation is commutative. Triggers the `combineCommutativity` law check on top of the inherited Monoid + Semigroup chain. Stdlib has no general CommutativeMonoid (only `AdditiveArithmetic` for `+`/`zero`-shaped commutative types).

### `Group` *(v1.9)*

- **Inherits:** `Monoid`
- **Requirement:** `static func inverse(_ x: Self) -> Self`
- A `Monoid` in which every element has a two-sided inverse. Two own Strict laws: `combineLeftInverse` and `combineRightInverse`. Static-method `inverse(_:)` form (not `inverted()` instance method, not `negated()`) keeps witness-extraction uniform with `combine(_:_:)` / `identity`. Group does NOT subsume `CommutativeMonoid` — non-commutative groups are valid (matrix groups, permutation groups), and the two are incomparable arms in the protocol DAG.

### `Semilattice` *(v1.9)*

- **Inherits:** `CommutativeMonoid`
- **Requirement:** none beyond CommutativeMonoid — marker protocol
- A `CommutativeMonoid` whose `combine` is idempotent (`combine(a, a) == a`). Bounded join-semilattices (`(Set<T>, ∪, ∅)`, `(Int, max, .min)`) and bounded meet-semilattices (`(Int, min, .max)`, `(Bool, &&, true)`) share this conformance — the law is symmetric.

### Roadmap

`Ring` is intentionally not yet shipped — two-op shape (additive group + multiplicative monoid + distributivity) doesn't fit the kit's single-op `combine`/`identity` pattern; designing a dual-witness or layered stack is reasonable v1.10+ work. SwiftInferProperties M8 still targets stdlib `Numeric` for the Ring promotion. `CommutativeGroup` is deferred — rare in idiomatic Swift since most everyday Abelian groups are integer/floating-point under `+` (already covered by `AdditiveArithmetic` / `Numeric`); SwiftInferProperties M8 emits separate `CommutativeMonoid` + `Group` proposals on the same type when both fire, which a future kit-side `CommutativeGroup` would collapse. `CommutativeSemigroup` is similarly deferred. `Functor` / `Applicative` / `Monad` are out of scope indefinitely.