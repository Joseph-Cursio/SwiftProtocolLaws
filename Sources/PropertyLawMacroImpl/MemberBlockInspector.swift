import PropertyLawCore
import SwiftSyntax

/// Pure SwiftSyntax helpers that walk a `MemberBlockSyntax` to extract
/// the syntactic info `DerivationStrategist` and `KnownProtocol` consumers
/// need. The macro impl uses these directly; the discovery plugin's
/// `ModuleScanner` uses an in-tree port (the discovery plugin doesn't
/// depend on `PropertyLawMacroImpl`, so the logic is duplicated by design —
/// see PRD §9 architecture decision 6 about plugin/macro separation).
enum MemberBlockInspector {

    /// Stored properties declared in `memberBlock`, in source order.
    /// Returns only `let`/`var` declarations with explicit type
    /// annotations and no accessor block (`{ get/set }` style computed
    /// properties are skipped). Multi-binding lines like `let x: Int, y: Int`
    /// produce one entry per binding.
    static func storedMembers(in memberBlock: MemberBlockSyntax) -> [StoredMember] {
        var result: [StoredMember] = []
        for member in memberBlock.members {
            guard let varDecl = member.decl.as(VariableDeclSyntax.self) else { continue }
            guard !isStaticOrClass(varDecl) else { continue }
            for binding in varDecl.bindings {
                if binding.accessorBlock != nil { continue }
                guard let identifier = binding.pattern.as(IdentifierPatternSyntax.self) else {
                    continue
                }
                guard let typeAnnotation = binding.typeAnnotation else { continue }
                let typeName = typeAnnotation.type.trimmedDescription
                result.append(StoredMember(
                    name: identifier.identifier.text,
                    typeName: typeName
                ))
            }
        }
        return result
    }

    /// True when the type's primary declaration body contains any `init`.
    /// Swift suppresses the synthesized memberwise initializer in that
    /// case — memberwise-Arbitrary derivation must fall through.
    static func hasUserInit(in memberBlock: MemberBlockSyntax) -> Bool {
        for member in memberBlock.members
        where member.decl.as(InitializerDeclSyntax.self) != nil {
            return true
        }
        return false
    }

    private static func isStaticOrClass(_ decl: VariableDeclSyntax) -> Bool {
        decl.modifiers.contains { mod in
            mod.name.tokenKind == .keyword(.static) || mod.name.tokenKind == .keyword(.class)
        }
    }
}
