import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import Testing
@testable import ProtoLawMacroImpl

@Suite struct DiagnosticsTests {

    // MARK: - typeNotInFile

    @Test func typeNotDeclaredInFileEmitsError() {
        assertMacroExpansion(
            """
            @ProtoLawSuite(types: [MissingType.self])
            struct Tests {
            }
            """,
            expandedSource: """
            struct Tests {
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: """
                        Type not declared in this file. @ProtoLawSuite scans the \
                        current file for declarations and extensions; cross-file \
                        discovery is the upcoming Swift Package Plugin (PRD §5.3).
                        """,
                    line: 1,
                    column: 23,
                    severity: .error
                )
            ],
            macros: testMacros
        )
    }

    // MARK: - noKnownConformance

    @Test func typeWithNoStdlibConformanceEmitsWarning() {
        assertMacroExpansion(
            """
            struct Foo: SomeCustomProtocol {
                let value: Int
            }
            @ProtoLawSuite(types: [Foo.self])
            struct Tests {
            }
            """,
            expandedSource: """
            struct Foo: SomeCustomProtocol {
                let value: Int
            }
            struct Tests {
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: """
                        Type has no recognized stdlib protocol conformance — no \
                        law checks emitted. Recognized protocols: Equatable, \
                        Hashable, Comparable, Codable, Sequence, Collection, \
                        SetAlgebra.
                        """,
                    line: 4,
                    column: 23,
                    severity: .warning
                )
            ],
            macros: testMacros
        )
    }

    // MARK: - malformedTypeElement

    @Test func nonMetatypeElementEmitsError() {
        // `MyType` (no `.self`) isn't a metatype literal.
        assertMacroExpansion(
            """
            struct MyType: Equatable {
                let value: Int
            }
            @ProtoLawSuite(types: [MyType])
            struct Tests {
            }
            """,
            expandedSource: """
            struct MyType: Equatable {
                let value: Int
            }
            struct Tests {
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: """
                        Each element of `types:` must be a metatype literal \
                        (e.g. `Foo.self`). Generic parameters, `type(of:)`, and \
                        type aliases aren't supported in M1.
                        """,
                    line: 4,
                    column: 23,
                    severity: .error
                )
            ],
            macros: testMacros
        )
    }

    // MARK: - IteratorProtocol-only triggers noKnownConformance after filter

    @Test func iteratorProtocolOnlyEmitsWarning() {
        // The scanner finds IteratorProtocol; the macro filters it out
        // (no usable kit call) and the empty post-filter set surfaces as
        // noKnownConformance — same diagnostic as a type with no recognized
        // stdlib protocols.
        assertMacroExpansion(
            """
            struct Cursor: IteratorProtocol {
                mutating func next() -> Int? { nil }
            }
            @ProtoLawSuite(types: [Cursor.self])
            struct Tests {
            }
            """,
            expandedSource: """
            struct Cursor: IteratorProtocol {
                mutating func next() -> Int? { nil }
            }
            struct Tests {
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: """
                        Type has no recognized stdlib protocol conformance — no \
                        law checks emitted. Recognized protocols: Equatable, \
                        Hashable, Comparable, Codable, Sequence, Collection, \
                        SetAlgebra.
                        """,
                    line: 4,
                    column: 23,
                    severity: .warning
                )
            ],
            macros: testMacros
        )
    }

    // MARK: - Mixing types — diagnose only the offender

    @Test func mixedValidAndInvalidTypesDiagnosesOnlyOffender() {
        assertMacroExpansion(
            """
            struct Foo: Equatable {
                let value: Int
            }
            @ProtoLawSuite(types: [Foo.self, MissingType.self])
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
            diagnostics: [
                DiagnosticSpec(
                    message: """
                        Type not declared in this file. @ProtoLawSuite scans the \
                        current file for declarations and extensions; cross-file \
                        discovery is the upcoming Swift Package Plugin (PRD §5.3).
                        """,
                    line: 4,
                    column: 34,
                    severity: .error
                )
            ],
            macros: testMacros
        )
    }
}
