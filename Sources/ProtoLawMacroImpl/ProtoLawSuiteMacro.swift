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
/// `IteratorProtocol`-only conformers receive no emit because the kit's
/// `checkIteratorProtocolLaws` is parameterized over a host `Sequence`
/// (PRD §4.3 IteratorProtocol). When the type conforms to `Sequence` the
/// inherited iterator laws still run via the kit's chain.
public struct ProtoLawSuiteMacro: MemberMacro {

    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        let typeNames = parseTypeNames(from: node)
        guard let sourceFile = declaration.root.as(SourceFileSyntax.self) else {
            return []
        }
        var members: [DeclSyntax] = []
        for typeName in typeNames {
            guard let conformances = ConformanceScanner.conformances(of: typeName, in: sourceFile)
            else { continue }
            for conformance in stableOrder(conformances) where shouldEmit(conformance) {
                members.append(emit(conformance: conformance, typeName: typeName))
            }
        }
        return members
    }

    /// Pulls bare type names out of the macro's `types:` array argument.
    /// Accepts only `Identifier.self` literals; anything else (generic
    /// parameters, `type(of:)`, type aliases) is silently dropped in M1
    /// and surfaces as a `malformedArgs` diagnostic in commit 4.
    private static func parseTypeNames(from node: AttributeSyntax) -> [String] {
        guard case .argumentList(let arguments) = node.arguments else { return [] }
        guard let typesArg = arguments.first(where: { $0.label?.text == "types" }) else {
            return []
        }
        guard let arrayExpr = typesArg.expression.as(ArrayExprSyntax.self) else { return [] }
        return arrayExpr.elements.compactMap { element in
            guard let memberAccess = element.expression.as(MemberAccessExprSyntax.self),
                  memberAccess.declName.baseName.text == "self",
                  let baseExpr = memberAccess.base
            else { return nil }
            return baseExpr.trimmedDescription
        }
    }

    /// Stable iteration order so the emit is deterministic across runs —
    /// the user reads a diff of generated tests, not a re-shuffle.
    private static func stableOrder(_ protocols: Set<KnownProtocol>) -> [KnownProtocol] {
        KnownProtocol.allCases.filter { protocols.contains($0) }
    }

    private static func shouldEmit(_ protocolEntry: KnownProtocol) -> Bool {
        // IteratorProtocol-only conformers have no usable kit call; the
        // kit's iterator suite is parameterized over a host Sequence.
        // (PRD §4.3 IteratorProtocol.) Drop the standalone case to avoid
        // emitting code that doesn't compile.
        protocolEntry != .iteratorProtocol
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
