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
}
