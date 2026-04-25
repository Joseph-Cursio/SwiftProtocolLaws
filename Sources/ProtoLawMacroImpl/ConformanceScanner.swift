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
            let decl = statement.item
            switch decl.as(DeclSyntax.self)?.kind {
            case .structDecl:
                if let structDecl = decl.as(StructDeclSyntax.self),
                   structDecl.name.text == typeName {
                    foundDeclaration = true
                    inheritedNames.append(contentsOf: names(in: structDecl.inheritanceClause))
                }
            case .classDecl:
                if let classDecl = decl.as(ClassDeclSyntax.self),
                   classDecl.name.text == typeName {
                    foundDeclaration = true
                    inheritedNames.append(contentsOf: names(in: classDecl.inheritanceClause))
                }
            case .enumDecl:
                if let enumDecl = decl.as(EnumDeclSyntax.self),
                   enumDecl.name.text == typeName {
                    foundDeclaration = true
                    inheritedNames.append(contentsOf: names(in: enumDecl.inheritanceClause))
                }
            case .actorDecl:
                if let actorDecl = decl.as(ActorDeclSyntax.self),
                   actorDecl.name.text == typeName {
                    foundDeclaration = true
                    inheritedNames.append(contentsOf: names(in: actorDecl.inheritanceClause))
                }
            case .extensionDecl:
                if let extensionDecl = decl.as(ExtensionDeclSyntax.self),
                   extendedTypeName(of: extensionDecl) == typeName {
                    foundDeclaration = true
                    // Skip extensions with a where clause — those are
                    // conditional conformances, M3+ scope (PRD §4.4 generic
                    // conformances). Adding the protocol here would falsely
                    // claim the type unconditionally conforms.
                    if extensionDecl.genericWhereClause == nil {
                        inheritedNames.append(contentsOf: names(in: extensionDecl.inheritanceClause))
                    }
                }
            default:
                continue
            }
        }

        guard foundDeclaration else { return nil }
        return KnownProtocol.mostSpecific(in: KnownProtocol.set(from: inheritedNames))
    }

    /// Pulls the bare protocol names from an `InheritanceClauseSyntax`. The
    /// extracted names are matched against `KnownProtocol.from(typeName:)`
    /// — exact-match semantics, no generic-arg stripping (the kit's covered
    /// protocols don't take generic arguments at the conformance site).
    private static func names(in clause: InheritanceClauseSyntax?) -> [String] {
        guard let clause else { return [] }
        return clause.inheritedTypes.compactMap { inheritedType in
            inheritedType.type.trimmedDescription
        }
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
