import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import Testing
@testable import ProtoLawMacroImpl

@Suite struct DiagnosticsTests {

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
}
