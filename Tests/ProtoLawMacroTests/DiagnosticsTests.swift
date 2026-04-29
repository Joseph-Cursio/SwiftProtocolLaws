import ProtoLawCore
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import Testing
@testable import ProtoLawMacroImpl

struct DiagnosticsTests {

    /// Direct `#expect` pin on the dynamic `noKnownConformance` message.
    /// `assertMacroExpansion` reports message mismatches via `XCTFail`,
    /// which Swift Testing's `@Test` doesn't always pick up — so the
    /// `DiagnosticSpec` literals in the other tests can drift silently.
    /// This test catches the drift directly at the `ProtoLawDiagnostic`
    /// surface.
    @Test func noKnownConformanceMessageListsEveryRecognizedProtocol() {
        let message = ProtoLawDiagnostic.noKnownConformance.message
        for known in KnownProtocol.allCases {
            #expect(
                message.contains(known.declarationName),
                "noKnownConformance message is missing \(known.declarationName)"
            )
        }
    }

    @Test func typeWithNoStdlibConformanceEmitsWarning() {
        assertMacroExpansion(
            """
            @ProtoLawSuite
            struct Foo: SomeCustomProtocol {
                let value: Int
            }
            """,
            expandedSource: """
            struct Foo: SomeCustomProtocol {
                let value: Int
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

    @Test func bareTypeNoInheritanceClauseEmitsWarning() {
        assertMacroExpansion(
            """
            @ProtoLawSuite
            struct Foo {
                let value: Int
            }
            """,
            expandedSource: """
            struct Foo {
                let value: Int
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

    // MARK: - cannotDeriveGenerator (M3)

    @Test func plainStructWithStdlibConformanceFiresCannotDeriveWarning() {
        // Equatable is recognized; the type has stdlib conformances and
        // gets law-check emit. But no derivation strategy applies (struct
        // without gen()), so the macro warns the user — alongside the
        // compile error from the missing Foo.gen() symbol.
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
            diagnostics: [
                DiagnosticSpec(
                    message: """
                        Cannot derive a generator for `Foo`: memberwise derivation \
                        isn't supported in M3 (deferred). Provide `static func gen() \
                        -> Generator<Foo, some SendableSequenceType>`.
                        """,
                    line: 1,
                    column: 1,
                    severity: .warning
                )
            ],
            macros: testMacros
        )
    }

    @Test func enumWithoutCaseIterableOrRawTypeFiresCannotDeriveWarning() {
        assertMacroExpansion(
            """
            @ProtoLawSuite
            enum Either: Equatable {
                case left, right
            }
            """,
            expandedSource: """
            enum Either: Equatable {
                case left, right
            }

            struct EitherProtocolLawTests {
                @Test func equatable_Either() async throws {
                        try await checkEquatableProtocolLaws(
                            for: Either.self,
                            using: Either.gen()
                        )
                    }
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: """
                        Cannot derive a generator for `Either`: not `CaseIterable` \
                        and no recognized stdlib raw type. Provide `static func \
                        gen() -> Generator<Either, some SendableSequenceType>` or \
                        add `: CaseIterable`.
                        """,
                    line: 1,
                    column: 1,
                    severity: .warning
                )
            ],
            macros: testMacros
        )
    }

    @Test func caseIterableEnumDoesNotFireCannotDeriveWarning() {
        // Derivation succeeds; no warning.
        assertMacroExpansion(
            """
            @ProtoLawSuite
            enum Status: CaseIterable, Equatable {
                case pending, active
            }
            """,
            expandedSource: """
            enum Status: CaseIterable, Equatable {
                case pending, active
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

    @Test func encodableAloneIsNotCodable() {
        // Codable requires both halves; an Encodable-only type doesn't get
        // a codable check emitted.
        assertMacroExpansion(
            """
            @ProtoLawSuite
            struct Halfway: Encodable {
                let id: Int
            }
            """,
            expandedSource: """
            struct Halfway: Encodable {
                let id: Int
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
}
