import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import Testing
@testable import ProtoLawMacroImpl

struct MacroExpansionMultiTypeTests {

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
                        Hashable, Comparable, Codable, IteratorProtocol, Sequence, \
                        Collection, BidirectionalCollection, RandomAccessCollection, \
                        MutableCollection, RangeReplaceableCollection, SetAlgebra, \
                        Strideable, RawRepresentable, LosslessStringConvertible, \
                        Identifiable, CaseIterable. Conformances declared via \
                        extensions outside the type's primary declaration aren't \
                        visible to the macro (it sees only the decoratee's syntax); \
                        whole-module discovery (PRD §5.3) handles those cases.
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

    @Test func stringRawRepresentableEnumDerivesGenerator() {
        // M3: enum + recognized stdlib raw type → derived generator
        // (Gen.<RawType>...compactMap { TypeName(rawValue: $0) }) instead
        // of the user's <TypeName>.gen() reference.
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
                            using: Gen<Character>.letterOrNumber.string(of: 0...8)
                                .compactMap { Direction(rawValue: $0) }
                        )
                    }

                @Test func codable_Direction() async throws {
                        try await checkCodableProtocolLaws(
                            for: Direction.self,
                            using: Gen<Character>.letterOrNumber.string(of: 0...8)
                                .compactMap { Direction(rawValue: $0) }
                        )
                    }
            }
            """,
            macros: testMacros
        )
    }

    @Test func caseIterableEnumDerivesAllCasesGenerator() {
        assertMacroExpansion(
            """
            @ProtoLawSuite
            enum Status: CaseIterable, Equatable {
                case pending, active, archived
            }
            """,
            expandedSource: """
            enum Status: CaseIterable, Equatable {
                case pending, active, archived
            }

            struct StatusProtocolLawTests {
                @Test func equatable_Status() async throws {
                        try await checkEquatableProtocolLaws(
                            for: Status.self,
                            using: Gen<Status>.element(of: Status.allCases)
                        )
                    }
            }
            """,
            macros: testMacros
        )
    }

    @Test func userGenInBodyOverridesDerivation() {
        // Even on a CaseIterable enum, defining `static func gen()` in the
        // type's primary body wins — the user's intent is the highest-
        // priority strategy in PRD §5.7.
        assertMacroExpansion(
            """
            @ProtoLawSuite
            enum Status: CaseIterable, Equatable {
                case pending, active

                static func gen() -> Generator<Status, some SendableSequenceType> {
                    Gen.element(of: Status.allCases)
                }
            }
            """,
            expandedSource: """
            enum Status: CaseIterable, Equatable {
                case pending, active

                static func gen() -> Generator<Status, some SendableSequenceType> {
                    Gen.element(of: Status.allCases)
                }
            }

            struct StatusProtocolLawTests {
                @Test func equatable_Status() async throws {
                        try await checkEquatableProtocolLaws(
                            for: Status.self,
                            using: Status.gen()
                        )
                    }
            }
            """,
            macros: testMacros
        )
    }
}
