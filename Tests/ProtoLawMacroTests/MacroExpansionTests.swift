import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import Testing
@testable import ProtoLawMacroImpl

/// Single source-of-truth macro registry for `assertMacroExpansion`. The
/// test target deliberately makes this `nonisolated(unsafe)` rather than
/// `@MainActor` — `assertMacroExpansion` itself isn't actor-isolated, and
/// the dictionary is read-only after init, so the access is safe in
/// practice.
nonisolated(unsafe) let testMacros: [String: Macro.Type] = [
    "ProtoLawSuite": ProtoLawSuiteMacro.self
]

@Suite struct MacroExpansionTests {

    // MARK: - Single-protocol expansions

    @Test func expandsEquatableConformance() {
        assertMacroExpansion(
            """
            struct Foo: Equatable {
                let value: Int
            }
            @ProtoLawSuite(types: [Foo.self])
            struct Tests {
                static let fooGen = Gen.foo()
            }
            """,
            expandedSource: """
            struct Foo: Equatable {
                let value: Int
            }
            struct Tests {
                static let fooGen = Gen.foo()

                @Test func equatable_Foo() async throws {
                    try await checkEquatableProtocolLaws(
                        for: Foo.self,
                        using: Self.fooGen
                    )
                }
            }
            """,
            macros: testMacros
        )
    }

    @Test func expandsHashableSubsumesEquatable() {
        assertMacroExpansion(
            """
            struct Foo: Equatable, Hashable {
                let value: Int
            }
            @ProtoLawSuite(types: [Foo.self])
            struct Tests {
                static let fooGen = Gen.foo()
            }
            """,
            expandedSource: """
            struct Foo: Equatable, Hashable {
                let value: Int
            }
            struct Tests {
                static let fooGen = Gen.foo()

                @Test func hashable_Foo() async throws {
                    try await checkHashableProtocolLaws(
                        for: Foo.self,
                        using: Self.fooGen
                    )
                }
            }
            """,
            macros: testMacros
        )
    }

    @Test func expandsComparableSubsumesEquatable() {
        assertMacroExpansion(
            """
            struct Foo: Comparable {
                let value: Int
                static func < (lhs: Foo, rhs: Foo) -> Bool { lhs.value < rhs.value }
            }
            @ProtoLawSuite(types: [Foo.self])
            struct Tests {
                static let fooGen = Gen.foo()
            }
            """,
            expandedSource: """
            struct Foo: Comparable {
                let value: Int
                static func < (lhs: Foo, rhs: Foo) -> Bool { lhs.value < rhs.value }
            }
            struct Tests {
                static let fooGen = Gen.foo()

                @Test func comparable_Foo() async throws {
                    try await checkComparableProtocolLaws(
                        for: Foo.self,
                        using: Self.fooGen
                    )
                }
            }
            """,
            macros: testMacros
        )
    }

    @Test func expandsCodable() {
        assertMacroExpansion(
            """
            struct Record: Codable, Equatable {
                let id: Int
            }
            @ProtoLawSuite(types: [Record.self])
            struct Tests {
                static let recordGen = Gen.record()
            }
            """,
            expandedSource: """
            struct Record: Codable, Equatable {
                let id: Int
            }
            struct Tests {
                static let recordGen = Gen.record()

                @Test func equatable_Record() async throws {
                    try await checkEquatableProtocolLaws(
                        for: Record.self,
                        using: Self.recordGen
                    )
                }

                @Test func codable_Record() async throws {
                    try await checkCodableProtocolLaws(
                        for: Record.self,
                        using: Self.recordGen
                    )
                }
            }
            """,
            macros: testMacros
        )
    }

    @Test func expandsCollectionSubsumesSequenceAndIterator() {
        assertMacroExpansion(
            """
            struct Pages: Collection {
                var startIndex: Int { 0 }
                var endIndex: Int { 0 }
                func index(after i: Int) -> Int { i + 1 }
                subscript(position: Int) -> Int { 0 }
            }
            @ProtoLawSuite(types: [Pages.self])
            struct Tests {
                static let pagesGen = Gen.pages()
            }
            """,
            expandedSource: """
            struct Pages: Collection {
                var startIndex: Int { 0 }
                var endIndex: Int { 0 }
                func index(after i: Int) -> Int { i + 1 }
                subscript(position: Int) -> Int { 0 }
            }
            struct Tests {
                static let pagesGen = Gen.pages()

                @Test func collection_Pages() async throws {
                    try await checkCollectionProtocolLaws(
                        for: Pages.self,
                        using: Self.pagesGen
                    )
                }
            }
            """,
            macros: testMacros
        )
    }
}
