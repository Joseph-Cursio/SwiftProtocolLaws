import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import Testing
@testable import ProtoLawMacroImpl

/// Single source-of-truth macro registry for `assertMacroExpansion`.
/// `nonisolated(unsafe)` because `assertMacroExpansion` itself isn't
/// actor-isolated; the dictionary is read-only after init.
nonisolated(unsafe) let testMacros: [String: Macro.Type] = [
    "ProtoLawSuite": ProtoLawSuiteMacro.self
]

// One golden-output test per emit-able protocol; the suite legitimately
// grows past SwiftLint's default body-length and file-length thresholds
// as new protocols ship. The disables are paired with an explicit
// re-enable at end of file.
// swiftlint:disable type_body_length file_length

struct MacroExpansionTests {

    @Test func equatableConformancesEmitsPeerSuite() {
        assertMacroExpansion(
            """
            @ProtoLawSuite
            struct Foo: Equatable {
                let value: Int
            }
            """,
            expandedSource: """
            struct Foo: Equatable {
                let value: Int
            }

            struct FooProtocolLawTests {
                @Test func equatable_Foo() async throws {
                        try await checkEquatableProtocolLaws(
                            for: Foo.self,
                            using: Foo.gen()
                        )
                    }
            }
            """,
            macros: testMacros
        )
    }

    @Test func hashableSubsumesEquatable() {
        assertMacroExpansion(
            """
            @ProtoLawSuite
            struct Foo: Equatable, Hashable {
                let value: Int
            }
            """,
            expandedSource: """
            struct Foo: Equatable, Hashable {
                let value: Int
            }

            struct FooProtocolLawTests {
                @Test func hashable_Foo() async throws {
                        try await checkHashableProtocolLaws(
                            for: Foo.self,
                            using: Foo.gen()
                        )
                    }
            }
            """,
            macros: testMacros
        )
    }

    @Test func comparableSubsumesEquatable() {
        assertMacroExpansion(
            """
            @ProtoLawSuite
            struct Foo: Comparable {
                let value: Int
                static func < (lhs: Foo, rhs: Foo) -> Bool { lhs.value < rhs.value }
            }
            """,
            expandedSource: """
            struct Foo: Comparable {
                let value: Int
                static func < (lhs: Foo, rhs: Foo) -> Bool { lhs.value < rhs.value }
            }

            struct FooProtocolLawTests {
                @Test func comparable_Foo() async throws {
                        try await checkComparableProtocolLaws(
                            for: Foo.self,
                            using: Foo.gen()
                        )
                    }
            }
            """,
            macros: testMacros
        )
    }

    @Test func identifiableEmitsIdStabilityCheck() {
        assertMacroExpansion(
            """
            @ProtoLawSuite
            struct User: Identifiable {
                let id: Int
                let name: String
            }
            """,
            expandedSource: """
            struct User: Identifiable {
                let id: Int
                let name: String
            }

            struct UserProtocolLawTests {
                @Test func identifiable_User() async throws {
                        try await checkIdentifiableProtocolLaws(
                            for: User.self,
                            using: User.gen()
                        )
                    }
            }
            """,
            macros: testMacros
        )
    }

    @Test func losslessStringConvertibleEmitsRoundTripCheck() {
        assertMacroExpansion(
            """
            @ProtoLawSuite
            struct Slug: LosslessStringConvertible, Equatable {
                let value: String
                init?(_ description: String) { self.value = description }
                var description: String { value }
            }
            """,
            expandedSource: """
            struct Slug: LosslessStringConvertible, Equatable {
                let value: String
                init?(_ description: String) { self.value = description }
                var description: String { value }
            }

            struct SlugProtocolLawTests {
                @Test func equatable_Slug() async throws {
                        try await checkEquatableProtocolLaws(
                            for: Slug.self,
                            using: Slug.gen()
                        )
                    }

                @Test func losslessStringConvertible_Slug() async throws {
                        try await checkLosslessStringConvertibleProtocolLaws(
                            for: Slug.self,
                            using: Slug.gen()
                        )
                    }
            }
            """,
            macros: testMacros
        )
    }

    @Test func rawRepresentableEmitsRoundTripCheck() {
        // Explicit `: RawRepresentable` in the inheritance clause emits
        // `checkRawRepresentableProtocolLaws`. Raw-value enums that
        // synthesize the conformance via `: String` / `: Int` etc. don't
        // match this detection — the macro only sees inheritance clauses
        // syntactically.
        assertMacroExpansion(
            """
            @ProtoLawSuite
            struct Token: RawRepresentable, Equatable {
                let rawValue: String
                init?(rawValue: String) { self.rawValue = rawValue }
            }
            """,
            expandedSource: """
            struct Token: RawRepresentable, Equatable {
                let rawValue: String
                init?(rawValue: String) { self.rawValue = rawValue }
            }

            struct TokenProtocolLawTests {
                @Test func equatable_Token() async throws {
                        try await checkEquatableProtocolLaws(
                            for: Token.self,
                            using: Token.gen()
                        )
                    }

                @Test func rawRepresentable_Token() async throws {
                        try await checkRawRepresentableProtocolLaws(
                            for: Token.self,
                            using: Token.gen()
                        )
                    }
            }
            """,
            macros: testMacros
        )
    }

    @Test func strideableSubsumesEmitsComparable() {
        // `Strideable` itself is unemittable — its check function takes a
        // `strideGenerator:` arg the macro can't synthesize from syntax alone.
        // But `Strideable` refines `Comparable` in stdlib, so `set(from:)`
        // auto-adds Comparable, and the macro emits `checkComparableProtocolLaws`
        // (which runs Equatable's laws first via inheritance at runtime).
        // Strideable's own laws stay a manual call.
        assertMacroExpansion(
            """
            @ProtoLawSuite
            struct Foo: Strideable {
                let value: Int
                static func < (lhs: Foo, rhs: Foo) -> Bool { lhs.value < rhs.value }
                func distance(to other: Foo) -> Int { other.value - value }
                func advanced(by step: Int) -> Foo { Foo(value: value + step) }
            }
            """,
            expandedSource: """
            struct Foo: Strideable {
                let value: Int
                static func < (lhs: Foo, rhs: Foo) -> Bool { lhs.value < rhs.value }
                func distance(to other: Foo) -> Int { other.value - value }
                func advanced(by step: Int) -> Foo { Foo(value: value + step) }
            }

            struct FooProtocolLawTests {
                @Test func comparable_Foo() async throws {
                        try await checkComparableProtocolLaws(
                            for: Foo.self,
                            using: Foo.gen()
                        )
                    }
            }
            """,
            macros: testMacros
        )
    }

    @Test func codableEmitsBothEquatableAndCodable() {
        assertMacroExpansion(
            """
            @ProtoLawSuite
            struct Record: Codable, Equatable {
                let id: Int
            }
            """,
            expandedSource: """
            struct Record: Codable, Equatable {
                let id: Int
            }

            struct RecordProtocolLawTests {
                @Test func equatable_Record() async throws {
                        try await checkEquatableProtocolLaws(
                            for: Record.self,
                            using: Record.gen()
                        )
                    }

                @Test func codable_Record() async throws {
                        try await checkCodableProtocolLaws(
                            for: Record.self,
                            using: Record.gen()
                        )
                    }
            }
            """,
            macros: testMacros
        )
    }

    @Test func collectionSubsumesSequenceAndIterator() {
        assertMacroExpansion(
            """
            @ProtoLawSuite
            struct Pages: Collection {
                var startIndex: Int { 0 }
                var endIndex: Int { 0 }
                func index(after i: Int) -> Int { i + 1 }
                subscript(position: Int) -> Int { 0 }
            }
            """,
            expandedSource: """
            struct Pages: Collection {
                var startIndex: Int { 0 }
                var endIndex: Int { 0 }
                func index(after i: Int) -> Int { i + 1 }
                subscript(position: Int) -> Int { 0 }
            }

            struct PagesProtocolLawTests {
                @Test func collection_Pages() async throws {
                        try await checkCollectionProtocolLaws(
                            for: Pages.self,
                            using: Pages.gen()
                        )
                    }
            }
            """,
            macros: testMacros
        )
    }

    @Test func randomAccessCollectionSubsumesBidirectionalAndCollection() {
        // RandomAccessCollection's subsumed set is transitive — a single
        // checkRandomAccessCollectionProtocolLaws call runs the inherited
        // BidirectionalCollection / Collection / Sequence / Iterator laws.
        assertMacroExpansion(
            """
            @ProtoLawSuite
            struct Pages: RandomAccessCollection, BidirectionalCollection, Collection {
                var startIndex: Int { 0 }
                var endIndex: Int { 0 }
                func index(after i: Int) -> Int { i + 1 }
                func index(before i: Int) -> Int { i - 1 }
                subscript(position: Int) -> Int { 0 }
            }
            """,
            expandedSource: """
            struct Pages: RandomAccessCollection, BidirectionalCollection, Collection {
                var startIndex: Int { 0 }
                var endIndex: Int { 0 }
                func index(after i: Int) -> Int { i + 1 }
                func index(before i: Int) -> Int { i - 1 }
                subscript(position: Int) -> Int { 0 }
            }

            struct PagesProtocolLawTests {
                @Test func randomAccessCollection_Pages() async throws {
                        try await checkRandomAccessCollectionProtocolLaws(
                            for: Pages.self,
                            using: Pages.gen()
                        )
                    }
            }
            """,
            macros: testMacros
        )
    }

    @Test func signedNumericSubsumesNumericAndAdditiveArithmetic() {
        // The algebraic chain refines AdditiveArithmetic ← Numeric ← SignedNumeric.
        // A type spelled `: SignedNumeric` should emit only the SignedNumeric
        // call; the inherited suites run at runtime via .all dispatch.
        assertMacroExpansion(
            """
            @ProtoLawSuite
            struct Quaternion: SignedNumeric {
                init(integerLiteral value: Int) {}
                init?(exactly source: some BinaryInteger) {}
                var magnitude: Int { 0 }
                static var zero: Quaternion { Quaternion(integerLiteral: 0) }
                static func + (a: Quaternion, b: Quaternion) -> Quaternion { a }
                static func - (a: Quaternion, b: Quaternion) -> Quaternion { a }
                static func * (a: Quaternion, b: Quaternion) -> Quaternion { a }
                static func *= (a: inout Quaternion, b: Quaternion) {}
            }
            """,
            expandedSource: """
            struct Quaternion: SignedNumeric {
                init(integerLiteral value: Int) {}
                init?(exactly source: some BinaryInteger) {}
                var magnitude: Int { 0 }
                static var zero: Quaternion { Quaternion(integerLiteral: 0) }
                static func + (a: Quaternion, b: Quaternion) -> Quaternion { a }
                static func - (a: Quaternion, b: Quaternion) -> Quaternion { a }
                static func * (a: Quaternion, b: Quaternion) -> Quaternion { a }
                static func *= (a: inout Quaternion, b: Quaternion) {}
            }

            struct QuaternionProtocolLawTests {
                @Test func signedNumeric_Quaternion() async throws {
                        try await checkSignedNumericProtocolLaws(
                            for: Quaternion.self,
                            using: Quaternion.gen()
                        )
                    }
            }
            """,
            macros: testMacros
        )
    }

    @Test func signedIntegerCollapsesDiamondToSingleEmission() {
        // SignedInteger refines BOTH BinaryInteger and SignedNumeric in stdlib.
        // The diamond should collapse under mostSpecific to a single
        // `checkSignedIntegerProtocolLaws` call; runtime dispatch through
        // .all then runs both inherited suites.
        assertMacroExpansion(
            """
            @ProtoLawSuite
            struct WideInt: SignedInteger {}
            """,
            expandedSource: """
            struct WideInt: SignedInteger {}

            struct WideIntProtocolLawTests {
                @Test func signedInteger_WideInt() async throws {
                        try await checkSignedIntegerProtocolLaws(
                            for: WideInt.self,
                            using: WideInt.gen()
                        )
                    }
            }
            """,
            macros: testMacros
        )
    }

    @Test func stringProtocolSubsumesBidirectionalCollectionChain() {
        // StringProtocol refines BidirectionalCollection (and transitively
        // Collection / Sequence / IteratorProtocol). Most-specific dedupe
        // collapses the chain to a single `checkStringProtocolLaws` call.
        // Hashable / Comparable / LosslessStringConvertible stay
        // unsubsumed — they test different invariants.
        assertMacroExpansion(
            """
            @ProtoLawSuite
            struct CharBuffer: StringProtocol {}
            """,
            expandedSource: """
            struct CharBuffer: StringProtocol {}

            struct CharBufferProtocolLawTests {
                @Test func stringProtocol_CharBuffer() async throws {
                        try await checkStringProtocolLaws(
                            for: CharBuffer.self,
                            using: CharBuffer.gen()
                        )
                    }
            }
            """,
            macros: testMacros
        )
    }

    @Test func binaryFloatingPointSubsumesFloatingPoint() {
        // BinaryFloatingPoint subsumes FloatingPoint and (transitively)
        // the algebraic chain. A type spelled `: BinaryFloatingPoint`
        // emits only the BinaryFloatingPoint check.
        assertMacroExpansion(
            """
            @ProtoLawSuite
            struct Quad: BinaryFloatingPoint {}
            """,
            expandedSource: """
            struct Quad: BinaryFloatingPoint {}

            struct QuadProtocolLawTests {
                @Test func binaryFloatingPoint_Quad() async throws {
                        try await checkBinaryFloatingPointProtocolLaws(
                            for: Quad.self,
                            using: Quad.gen()
                        )
                    }
            }
            """,
            macros: testMacros
        )
    }

    @Test func floatingPointSubsumesAlgebraicChain() {
        // FloatingPoint subsumes SignedNumeric → Numeric → AdditiveArithmetic
        // because exact-equality algebraic laws don't hold on IEEE-754. A
        // type spelled `: FloatingPoint` emits only the FloatingPoint check.
        assertMacroExpansion(
            """
            @ProtoLawSuite
            struct Quad: FloatingPoint {}
            """,
            expandedSource: """
            struct Quad: FloatingPoint {}

            struct QuadProtocolLawTests {
                @Test func floatingPoint_Quad() async throws {
                        try await checkFloatingPointProtocolLaws(
                            for: Quad.self,
                            using: Quad.gen()
                        )
                    }
            }
            """,
            macros: testMacros
        )
    }

    @Test func fixedWidthAndSignedIntegerSurviveAsSiblings() {
        // FixedWidthInteger and SignedInteger are independent siblings —
        // FixedWidthInteger refines BinaryInteger, SignedInteger refines
        // BinaryInteger and SignedNumeric, neither subsumes the other.
        // Both checks should emit (matches the v1.2 Mutable+Bidirectional
        // sibling pattern).
        assertMacroExpansion(
            """
            @ProtoLawSuite
            struct Word: FixedWidthInteger, SignedInteger {}
            """,
            expandedSource: """
            struct Word: FixedWidthInteger, SignedInteger {}

            struct WordProtocolLawTests {
                @Test func fixedWidthInteger_Word() async throws {
                        try await checkFixedWidthIntegerProtocolLaws(
                            for: Word.self,
                            using: Word.gen()
                        )
                    }

                @Test func signedInteger_Word() async throws {
                        try await checkSignedIntegerProtocolLaws(
                            for: Word.self,
                            using: Word.gen()
                        )
                    }
            }
            """,
            macros: testMacros
        )
    }

    @Test func unsignedIntegerCollapsesToSingleEmission() {
        // UnsignedInteger subsumes BinaryInteger → Numeric → AdditiveArithmetic.
        // Single emission expected.
        assertMacroExpansion(
            """
            @ProtoLawSuite
            struct BigUInt: UnsignedInteger {}
            """,
            expandedSource: """
            struct BigUInt: UnsignedInteger {}

            struct BigUIntProtocolLawTests {
                @Test func unsignedInteger_BigUInt() async throws {
                        try await checkUnsignedIntegerProtocolLaws(
                            for: BigUInt.self,
                            using: BigUInt.gen()
                        )
                    }
            }
            """,
            macros: testMacros
        )
    }

    @Test func mutableAndRangeReplaceableSurviveAsSiblings() {
        // MutableCollection and RangeReplaceableCollection are independent
        // refinements of Collection — neither subsumes the other, so both
        // emit alongside RandomAccessCollection.
        assertMacroExpansion(
            """
            @ProtoLawSuite
            struct Buffer: RandomAccessCollection, MutableCollection, RangeReplaceableCollection {
                init() {}
                var startIndex: Int { 0 }
                var endIndex: Int { 0 }
                func index(after i: Int) -> Int { i + 1 }
                func index(before i: Int) -> Int { i - 1 }
                subscript(position: Int) -> Int { get { 0 } set {} }
                mutating func replaceSubrange<C: Collection>(_ s: Range<Int>, with c: C) where C.Element == Int {}
            }
            """,
            expandedSource: """
            struct Buffer: RandomAccessCollection, MutableCollection, RangeReplaceableCollection {
                init() {}
                var startIndex: Int { 0 }
                var endIndex: Int { 0 }
                func index(after i: Int) -> Int { i + 1 }
                func index(before i: Int) -> Int { i - 1 }
                subscript(position: Int) -> Int { get { 0 } set {} }
                mutating func replaceSubrange<C: Collection>(_ s: Range<Int>, with c: C) where C.Element == Int {}
            }

            struct BufferProtocolLawTests {
                @Test func randomAccessCollection_Buffer() async throws {
                        try await checkRandomAccessCollectionProtocolLaws(
                            for: Buffer.self,
                            using: Buffer.gen()
                        )
                    }

                @Test func mutableCollection_Buffer() async throws {
                        try await checkMutableCollectionProtocolLaws(
                            for: Buffer.self,
                            using: Buffer.gen()
                        )
                    }

                @Test func rangeReplaceableCollection_Buffer() async throws {
                        try await checkRangeReplaceableCollectionProtocolLaws(
                            for: Buffer.self,
                            using: Buffer.gen()
                        )
                    }
            }
            """,
            macros: testMacros
        )
    }

    // MARK: - v1.8 kit-defined algebraic protocols

    @Test func semigroupConformanceEmitsPeerSuite() {
        assertMacroExpansion(
            """
            @ProtoLawSuite
            struct Counter: Semigroup {
                let value: Int
            }
            """,
            expandedSource: """
            struct Counter: Semigroup {
                let value: Int
            }

            struct CounterProtocolLawTests {
                @Test func semigroup_Counter() async throws {
                        try await checkSemigroupProtocolLaws(
                            for: Counter.self,
                            using: Counter.gen()
                        )
                    }
            }
            """,
            macros: testMacros
        )
    }

    @Test func monoidSubsumesSemigroup() {
        // Monoid refines kit-defined Semigroup. A type spelled
        // `: Semigroup, Monoid` should emit only the Monoid call —
        // checkMonoidProtocolLaws auto-runs Semigroup's law via .all.
        assertMacroExpansion(
            """
            @ProtoLawSuite
            struct Tally: Semigroup, Monoid {}
            """,
            expandedSource: """
            struct Tally: Semigroup, Monoid {}

            struct TallyProtocolLawTests {
                @Test func monoid_Tally() async throws {
                        try await checkMonoidProtocolLaws(
                            for: Tally.self,
                            using: Tally.gen()
                        )
                    }
            }
            """,
            macros: testMacros
        )
    }

    @Test func bareMonoidConformanceEmitsMonoidCall() {
        // A type spelled `: Monoid` alone (Semigroup implied by refinement)
        // emits the Monoid check with no Semigroup duplicate.
        assertMacroExpansion(
            """
            @ProtoLawSuite
            struct Tally: Monoid {}
            """,
            expandedSource: """
            struct Tally: Monoid {}

            struct TallyProtocolLawTests {
                @Test func monoid_Tally() async throws {
                        try await checkMonoidProtocolLaws(
                            for: Tally.self,
                            using: Tally.gen()
                        )
                    }
            }
            """,
            macros: testMacros
        )
    }

    // MARK: - v1.9 kit-defined CommutativeMonoid / Group / Semilattice

    @Test func commutativeMonoidSubsumesMonoidAndSemigroup() {
        // CommutativeMonoid refines Monoid (and transitively Semigroup).
        // A type spelled `: Semigroup, Monoid, CommutativeMonoid` emits
        // only the CommutativeMonoid call.
        assertMacroExpansion(
            """
            @ProtoLawSuite
            struct Tally: Semigroup, Monoid, CommutativeMonoid {}
            """,
            expandedSource: """
            struct Tally: Semigroup, Monoid, CommutativeMonoid {}

            struct TallyProtocolLawTests {
                @Test func commutativeMonoid_Tally() async throws {
                        try await checkCommutativeMonoidProtocolLaws(
                            for: Tally.self,
                            using: Tally.gen()
                        )
                    }
            }
            """,
            macros: testMacros
        )
    }

    @Test func bareCommutativeMonoidConformanceEmitsCMonCall() {
        assertMacroExpansion(
            """
            @ProtoLawSuite
            struct Tally: CommutativeMonoid {}
            """,
            expandedSource: """
            struct Tally: CommutativeMonoid {}

            struct TallyProtocolLawTests {
                @Test func commutativeMonoid_Tally() async throws {
                        try await checkCommutativeMonoidProtocolLaws(
                            for: Tally.self,
                            using: Tally.gen()
                        )
                    }
            }
            """,
            macros: testMacros
        )
    }

    @Test func groupSubsumesMonoidAndSemigroup() {
        // Group refines Monoid; non-commutative groups are valid so Group
        // does NOT subsume CommutativeMonoid. A type spelled
        // `: Monoid, Group` emits only the Group call.
        assertMacroExpansion(
            """
            @ProtoLawSuite
            struct AdditiveInt: Monoid, Group {}
            """,
            expandedSource: """
            struct AdditiveInt: Monoid, Group {}

            struct AdditiveIntProtocolLawTests {
                @Test func group_AdditiveInt() async throws {
                        try await checkGroupProtocolLaws(
                            for: AdditiveInt.self,
                            using: AdditiveInt.gen()
                        )
                    }
            }
            """,
            macros: testMacros
        )
    }

    @Test func commutativeMonoidAndGroupAreIncomparable() {
        // CommutativeMonoid and Group are incomparable arms in the
        // protocol DAG (kit-side CommutativeGroup is out of v1.9 scope).
        // A type spelled `: CommutativeMonoid, Group` emits BOTH calls.
        assertMacroExpansion(
            """
            @ProtoLawSuite
            struct AdditiveInt: CommutativeMonoid, Group {}
            """,
            expandedSource: """
            struct AdditiveInt: CommutativeMonoid, Group {}

            struct AdditiveIntProtocolLawTests {
                @Test func commutativeMonoid_AdditiveInt() async throws {
                        try await checkCommutativeMonoidProtocolLaws(
                            for: AdditiveInt.self,
                            using: AdditiveInt.gen()
                        )
                    }
                @Test func group_AdditiveInt() async throws {
                        try await checkGroupProtocolLaws(
                            for: AdditiveInt.self,
                            using: AdditiveInt.gen()
                        )
                    }
            }
            """,
            macros: testMacros
        )
    }

    @Test func semilatticeSubsumesCommutativeMonoidChain() {
        // Semilattice refines CommutativeMonoid (and transitively Monoid +
        // Semigroup). A type spelled with the full chain emits only the
        // Semilattice call.
        assertMacroExpansion(
            """
            @ProtoLawSuite
            struct MaxInt: Semigroup, Monoid, CommutativeMonoid, Semilattice {}
            """,
            expandedSource: """
            struct MaxInt: Semigroup, Monoid, CommutativeMonoid, Semilattice {}

            struct MaxIntProtocolLawTests {
                @Test func semilattice_MaxInt() async throws {
                        try await checkSemilatticeProtocolLaws(
                            for: MaxInt.self,
                            using: MaxInt.gen()
                        )
                    }
            }
            """,
            macros: testMacros
        )
    }

    @Test func bareSemilatticeConformanceEmitsSemilatticeCall() {
        assertMacroExpansion(
            """
            @ProtoLawSuite
            struct MaxInt: Semilattice {}
            """,
            expandedSource: """
            struct MaxInt: Semilattice {}

            struct MaxIntProtocolLawTests {
                @Test func semilattice_MaxInt() async throws {
                        try await checkSemilatticeProtocolLaws(
                            for: MaxInt.self,
                            using: MaxInt.gen()
                        )
                    }
            }
            """,
            macros: testMacros
        )
    }
}

// swiftlint:enable type_body_length file_length
