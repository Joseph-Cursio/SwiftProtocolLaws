import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

/// `@ProtoLawSuite` peer macro implementation.
///
/// Given a type declaration, reads its inheritance clause, filters down to
/// the most-specific recognized stdlib conformances (PRD §4.3 inheritance
/// rule), and emits a peer `@Suite` struct of `@Test func` methods — one
/// per surviving conformance, calling the corresponding
/// `checkXxxProtocolLaws(...)` against `<TypeName>.gen()`.
///
/// `IteratorProtocol`-only conformers receive no emit because the kit's
/// `checkIteratorProtocolLaws` is parameterized over a host `Sequence`.
public struct ProtoLawSuiteMacro: PeerMacro {

    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let target = TargetDecl(declaration: declaration) else {
            context.diagnose(Diagnostic(
                node: declaration,
                message: ProtoLawDiagnostic.nonTypeDecl
            ))
            return []
        }
        let inheritedNames = inheritedTypeNames(of: target.inheritanceClause)
        let conformances = KnownProtocol.set(from: inheritedNames)
        let mostSpecific = KnownProtocol.mostSpecific(in: conformances)
        let emitSet = mostSpecific.filter { $0 != .iteratorProtocol }
        if emitSet.isEmpty {
            context.diagnose(Diagnostic(
                node: declaration,
                message: ProtoLawDiagnostic.noKnownConformance
            ))
            return []
        }
        return [emitPeerSuite(typeName: target.name, conformances: emitSet)]
    }

    /// One of the four type-decl shapes a peer macro can attach to. Bundles
    /// the type name + inheritance clause so the rest of the expansion is
    /// kind-agnostic.
    private struct TargetDecl {
        let name: String
        let inheritanceClause: InheritanceClauseSyntax?

        init?(declaration: some DeclSyntaxProtocol) {
            if let structDecl = declaration.as(StructDeclSyntax.self) {
                self.name = structDecl.name.text
                self.inheritanceClause = structDecl.inheritanceClause
            } else if let classDecl = declaration.as(ClassDeclSyntax.self) {
                self.name = classDecl.name.text
                self.inheritanceClause = classDecl.inheritanceClause
            } else if let enumDecl = declaration.as(EnumDeclSyntax.self) {
                self.name = enumDecl.name.text
                self.inheritanceClause = enumDecl.inheritanceClause
            } else if let actorDecl = declaration.as(ActorDeclSyntax.self) {
                self.name = actorDecl.name.text
                self.inheritanceClause = actorDecl.inheritanceClause
            } else {
                return nil
            }
        }
    }

    private static func inheritedTypeNames(of clause: InheritanceClauseSyntax?) -> [String] {
        guard let clause else { return [] }
        return clause.inheritedTypes.compactMap { $0.type.trimmedDescription }
    }

    private static func emitPeerSuite(
        typeName: String,
        conformances: Set<KnownProtocol>
    ) -> DeclSyntax {
        let testMethods = stableOrder(conformances).map { conformance in
            emitTest(conformance: conformance, typeName: typeName)
        }.joined(separator: "\n\n    ")
        // No `@Suite` annotation: Swift Testing's macro can't be reliably
        // composed inside our peer expansion — its private file-scope
        // symbols don't resolve from within another macro's emitted scope.
        // Bare `@Test` methods inside a struct are still discovered by the
        // Swift Testing runner; users who want a named suite annotation
        // can apply `@Suite("custom name")` manually to the emitted type
        // (or wrap the type in another that's @Suite-annotated).
        return """
            struct \(raw: typeName)ProtocolLawTests {
                \(raw: testMethods)
            }
            """
    }

    /// Stable iteration order so the emit is deterministic across runs —
    /// the user reads a diff of generated tests, not a re-shuffle.
    private static func stableOrder(_ protocols: Set<KnownProtocol>) -> [KnownProtocol] {
        KnownProtocol.allCases.filter { protocols.contains($0) }
    }

    private static func emitTest(conformance: KnownProtocol, typeName: String) -> String {
        let testFuncName = "\(conformance.testNameFragment)_\(typeName)"
        let checkFn = conformance.checkFunctionName
        return """
            @Test func \(testFuncName)() async throws {
                    try await \(checkFn)(
                        for: \(typeName).self,
                        using: \(typeName).gen()
                    )
                }
            """
    }
}
