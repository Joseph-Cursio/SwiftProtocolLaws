import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import Testing
@testable import ProtoLawMacroImpl

private let testMacros: [String: Macro.Type] = [
    "ProtoLawSuite": ProtoLawSuiteMacro.self
]

@Suite struct MacroExpansionTests {

    @Test func skeletonExpandsWithSentinelMember() {
        assertMacroExpansion(
            """
            @ProtoLawSuite(types: [Foo.self])
            struct Tests {
            }
            """,
            expandedSource: """
            struct Tests {

                // ProtoLawSuite expansion placeholder. Real members land in commit 3.
                static let _protoLawSuitePlaceholder: Void = ()
            }
            """,
            macros: testMacros
        )
    }
}
