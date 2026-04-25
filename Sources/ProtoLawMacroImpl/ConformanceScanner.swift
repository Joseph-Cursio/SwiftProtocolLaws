import SwiftSyntax

/// Scans a `SourceFileSyntax` for the declarations and extensions of a
/// named type and reads their inheritance clauses. Returns `nil` when no
/// declaration is found in the file — the macro uses that to emit the
/// `typeNotInFile` diagnostic.
internal enum ConformanceScanner {

    static func conformances(of typeName: String, in file: SourceFileSyntax) -> Set<KnownProtocol>? {
        var inheritedNames: [String] = []
        var foundDeclaration = false

        for statement in file.statements {
            let match = inheritedNamesIfMatching(typeName: typeName, decl: statement.item)
            switch match {
            case .none:
                continue
            case .matchedNoConformances:
                foundDeclaration = true
            case .matchedWithConformances(let names):
                foundDeclaration = true
                inheritedNames.append(contentsOf: names)
            }
        }

        guard foundDeclaration else { return nil }
        return KnownProtocol.mostSpecific(in: KnownProtocol.set(from: inheritedNames))
    }

    /// Outcome of inspecting a single top-level statement against the named
    /// type. Distinguishes "not this type" from "this type, no conformances
    /// declared here" — the latter still counts toward `foundDeclaration`
    /// so we don't false-positive the `typeNotInFile` diagnostic on a
    /// type that happens to declare no stdlib conformances.
    private enum DeclMatch {
        case none
        case matchedNoConformances
        case matchedWithConformances([String])
    }

    private static func inheritedNamesIfMatching(
        typeName: String,
        decl: CodeBlockItemSyntax.Item
    ) -> DeclMatch {
        if let structDecl = decl.as(StructDeclSyntax.self), structDecl.name.text == typeName {
            return matched(clause: structDecl.inheritanceClause)
        }
        if let classDecl = decl.as(ClassDeclSyntax.self), classDecl.name.text == typeName {
            return matched(clause: classDecl.inheritanceClause)
        }
        if let enumDecl = decl.as(EnumDeclSyntax.self), enumDecl.name.text == typeName {
            return matched(clause: enumDecl.inheritanceClause)
        }
        if let actorDecl = decl.as(ActorDeclSyntax.self), actorDecl.name.text == typeName {
            return matched(clause: actorDecl.inheritanceClause)
        }
        if let extensionDecl = decl.as(ExtensionDeclSyntax.self),
           extendedTypeName(of: extensionDecl) == typeName {
            // Skip extensions with a where clause — those are conditional
            // conformances (PRD §4.4 generic conformances), M3+ scope.
            // Adding the protocol here would falsely claim unconditional
            // conformance.
            if extensionDecl.genericWhereClause != nil {
                return .matchedNoConformances
            }
            return matched(clause: extensionDecl.inheritanceClause)
        }
        return .none
    }

    private static func matched(clause: InheritanceClauseSyntax?) -> DeclMatch {
        guard let clause else { return .matchedNoConformances }
        let names = clause.inheritedTypes.compactMap { $0.type.trimmedDescription }
        return names.isEmpty ? .matchedNoConformances : .matchedWithConformances(names)
    }

    /// Bare type-name from an extension's `extendedType`. For
    /// `extension Foo.Bar` this returns `"Bar"` — we only support extensions
    /// of top-level types in M1 (the macro's same-file constraint already
    /// limits scope; nested-type expansion is M2+).
    private static func extendedTypeName(of extensionDecl: ExtensionDeclSyntax) -> String? {
        let typeText = extensionDecl.extendedType.trimmedDescription
        return typeText.split(separator: ".").last.map(String.init)
    }
}
