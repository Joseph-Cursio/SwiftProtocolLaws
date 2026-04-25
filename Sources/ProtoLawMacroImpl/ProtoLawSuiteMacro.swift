import SwiftSyntax
import SwiftSyntaxMacros

/// `@ProtoLawSuite(types: [...])` member macro implementation.
///
/// Commit 1 ships the skeleton: validates the macro is attached to a type
/// declaration and emits a sentinel comment-bearing member so end-to-end
/// compilation works. Conformance scanning + real expansion arrive in
/// commits 2 and 3.
public struct ProtoLawSuiteMacro: MemberMacro {

    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        // Skeleton expansion. Commits 2–3 will replace this with real
        // conformance-driven `@Test func` emission.
        let sentinel: DeclSyntax = """
            // ProtoLawSuite expansion placeholder. Real members land in commit 3.
            static let _protoLawSuitePlaceholder: Void = ()
            """
        return [sentinel]
    }
}
