import ProtoLawCore
import SwiftSyntax

/// Pure SwiftSyntax helpers for the discovery plugin's `ModuleScanner` —
/// extracts the stored-member info `DerivationStrategist` reads for the
/// memberwise-Arbitrary strategy. Mirrors `ProtoLawMacroImpl`'s
/// `MemberBlockInspector` line-for-line; the macro target and the
/// plugin target don't share code (PRD §9 Decision 4: discovery plugin
/// stays independent of `ProtoLawMacroImpl` so the macro's compile-time
/// dependency surface stays minimal).
enum PluginMemberInspector {

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
