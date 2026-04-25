import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

/// `@ProtoLawSuite(types: [...])` member macro implementation.
///
/// For each named type in the macro's `types:` argument:
/// 1. Locates the type's declaration (and any extensions) in the surrounding
///    source file via `ConformanceScanner`.
/// 2. Filters the recognized stdlib conformances down to the most-specific
///    set per PRD §4.3 inheritance semantics.
/// 3. Emits one `@Test func` per surviving conformance, calling the
///    corresponding `checkXxxProtocolLaws(...)` against
///    `Self.<typeName lowerCamel>Gen`.
///
/// Emits diagnostics for malformed args, malformed individual type
/// elements, types not declared in the current file (with a hint about the
/// upcoming Discovery plugin), and types whose conformances aren't
/// recognized. `IteratorProtocol`-only conformers receive no emit because
/// the kit's `checkIteratorProtocolLaws` is parameterized over a host
/// `Sequence` (PRD §4.3 IteratorProtocol).
public struct ProtoLawSuiteMacro: MemberMacro {

    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        let typeElements = parseTypeElements(from: node, in: context)
        guard let sourceFile = declaration.root.as(SourceFileSyntax.self) else {
            return []
        }
        var members: [DeclSyntax] = []
        for element in typeElements {
            guard let conformances = ConformanceScanner.conformances(
                of: element.typeName,
                in: sourceFile
            ) else {
                context.diagnose(Diagnostic(
                    node: element.node,
                    message: ProtoLawDiagnostic.typeNotInFile
                ))
                continue
            }
            let emitSet = conformances.filter { $0 != .iteratorProtocol }
            if emitSet.isEmpty {
                context.diagnose(Diagnostic(
                    node: element.node,
                    message: ProtoLawDiagnostic.noKnownConformance
                ))
                continue
            }
            for conformance in stableOrder(emitSet) {
                members.append(emit(conformance: conformance, typeName: element.typeName))
            }
        }
        return members
    }

    /// Single recognized `Foo.self` element from the macro's `types:` array.
    /// `node` is the original syntax for diagnostic anchoring.
    private struct TypeElement {
        let typeName: String
        let node: Syntax
    }

    /// Parses the `types: [...]` argument into a list of recognized
    /// `Foo.self` elements. Emits `malformedArgs` if the argument list
    /// itself isn't shaped right; emits `malformedTypeElement` for each
    /// element that isn't a metatype literal.
    private static func parseTypeElements(
        from node: AttributeSyntax,
        in context: some MacroExpansionContext
    ) -> [TypeElement] {
        guard
            case .argumentList(let arguments) = node.arguments,
            let typesArg = arguments.first(where: { $0.label?.text == "types" }),
            let arrayExpr = typesArg.expression.as(ArrayExprSyntax.self)
        else {
            context.diagnose(Diagnostic(
                node: node,
                message: ProtoLawDiagnostic.malformedArgs
            ))
            return []
        }
        return arrayExpr.elements.compactMap { element in
            guard
                let memberAccess = element.expression.as(MemberAccessExprSyntax.self),
                memberAccess.declName.baseName.text == "self",
                let baseExpr = memberAccess.base
            else {
                context.diagnose(Diagnostic(
                    node: element,
                    message: ProtoLawDiagnostic.malformedTypeElement
                ))
                return nil
            }
            return TypeElement(
                typeName: baseExpr.trimmedDescription,
                node: Syntax(element)
            )
        }
    }

    /// Stable iteration order so the emit is deterministic across runs —
    /// the user reads a diff of generated tests, not a re-shuffle.
    private static func stableOrder(_ protocols: Set<KnownProtocol>) -> [KnownProtocol] {
        KnownProtocol.allCases.filter { protocols.contains($0) }
    }

    private static func emit(conformance: KnownProtocol, typeName: String) -> DeclSyntax {
        let testFuncName = "\(conformance.testNameFragment)_\(typeName)"
        let generatorMember = generatorName(for: typeName)
        let checkFn = conformance.checkFunctionName
        return """
            @Test func \(raw: testFuncName)() async throws {
                try await \(raw: checkFn)(
                    for: \(raw: typeName).self,
                    using: Self.\(raw: generatorMember)
                )
            }
            """
    }

    /// Convention: `<TypeName>` → `<typeName>Gen` (first letter lowercased).
    /// `Foo` → `fooGen`, `URLLoader` → `uRLLoaderGen`. Imperfect for
    /// acronyms but consistent and grep-able. M3's generator derivation
    /// removes the convention requirement.
    private static func generatorName(for typeName: String) -> String {
        guard let first = typeName.first else { return "gen" }
        return first.lowercased() + typeName.dropFirst() + "Gen"
    }
}
