import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import Testing
@testable import ProtoLawMacroImpl

@Suite struct MacroExpansionMultiTypeTests {

    @Test func setAlgebraEmitsBothEquatableAndSetAlgebra() {
        assertMacroExpansion(
            """
            @ProtoLawSuite
            struct Bag: SetAlgebra, Equatable {
                init() {}
            }
            """,
            expandedSource: """
            struct Bag: SetAlgebra, Equatable {
                init() {}
            }

            struct BagProtocolLawTests {
                @Test func equatable_Bag() async throws {
                        try await checkEquatableProtocolLaws(
                            for: Bag.self,
                            using: Bag.gen()
                        )
                    }

                @Test func setAlgebra_Bag() async throws {
                        try await checkSetAlgebraProtocolLaws(
                            for: Bag.self,
                            using: Bag.gen()
                        )
                    }
            }
            """,
            macros: testMacros
        )
    }

    @Test func iteratorProtocolOnlyEmitsNothingAndWarns() {
        assertMacroExpansion(
            """
            @ProtoLawSuite
            struct Cursor: IteratorProtocol {
                mutating func next() -> Int? { nil }
            }
            """,
            expandedSource: """
            struct Cursor: IteratorProtocol {
                mutating func next() -> Int? { nil }
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: """
                        Type has no recognized stdlib protocol conformance — no \
                        law checks emitted. Recognized protocols: Equatable, \
                        Hashable, Comparable, Codable, Sequence, Collection, \
                        SetAlgebra. Conformances declared via extensions outside \
                        the type's primary declaration aren't visible to the macro \
                        (it sees only the decoratee's syntax); upcoming whole-module \
                        discovery (PRD §5.3) handles those cases.
                        """,
                    line: 1,
                    column: 1,
                    severity: .warning
                )
            ],
            macros: testMacros
        )
    }

    @Test func unconditionalSendableConformanceIsIgnored() {
        // Sendable + custom protocols are silently ignored; recognized
        // stdlib protocols still surface.
        assertMacroExpansion(
            """
            @ProtoLawSuite
            struct Foo: Sendable, MyCustomProto, Equatable {
                let value: Int
            }
            """,
            expandedSource: """
            struct Foo: Sendable, MyCustomProto, Equatable {
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

    @Test func encodableDecodablePairResolvesToCodable() {
        assertMacroExpansion(
            """
            @ProtoLawSuite
            struct Record: Encodable, Decodable, Equatable {
                let id: Int
            }
            """,
            expandedSource: """
            struct Record: Encodable, Decodable, Equatable {
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

    @Test func enumWithStdlibConformanceEmits() {
        assertMacroExpansion(
            """
            @ProtoLawSuite
            enum Direction: String, Codable, Equatable {
                case north, south, east, west
            }
            """,
            expandedSource: """
            enum Direction: String, Codable, Equatable {
                case north, south, east, west
            }

            struct DirectionProtocolLawTests {
                @Test func equatable_Direction() async throws {
                        try await checkEquatableProtocolLaws(
                            for: Direction.self,
                            using: Direction.gen()
                        )
                    }

                @Test func codable_Direction() async throws {
                        try await checkCodableProtocolLaws(
                            for: Direction.self,
                            using: Direction.gen()
                        )
                    }
            }
            """,
            macros: testMacros
        )
    }
}
