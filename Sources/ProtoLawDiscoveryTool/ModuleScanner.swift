import Foundation
import ProtoLawCore
import SwiftSyntax
import SwiftParser

/// Walks every `.swift` file in a target and aggregates type declarations
/// + their inheritance clauses (including extensions in other files) into
/// a single `ConformanceMap`.
///
/// Per-file errors are collected (file unreadable, etc.) rather than fatal
/// — the user gets a partial map plus a `parseFailures` list the emitter
/// can surface in the generated header.
enum ModuleScanner {

    static func scan(sourceFiles: [String]) -> ConformanceMap {
        var perType: [String: TypeAggregate] = [:]
        var failures: [ConformanceMap.ParseFailure] = []

        // Sorted input → sorted scan order → deterministic output.
        for filePath in sourceFiles.sorted() {
            let source: String
            do {
                source = try String(contentsOfFile: filePath, encoding: .utf8)
            } catch {
                failures.append(ConformanceMap.ParseFailure(
                    filePath: filePath,
                    message: "could not read file: \(error.localizedDescription)"
                ))
                continue
            }
            let parsed = Parser.parse(source: source)
            let converter = SourceLocationConverter(fileName: filePath, tree: parsed)
            for statement in parsed.statements {
                accumulate(
                    statement: statement.item,
                    context: RecordingContext(filePath: filePath, converter: converter),
                    into: &perType
                )
            }
        }
        return ConformanceMap(
            entries: makeEntries(from: perType),
            parseFailures: failures,
            witnesses: makeWitnesses(from: perType)
        )
    }

    private static func makeWitnesses(
        from perType: [String: TypeAggregate]
    ) -> [String: WitnessSet] {
        var result: [String: WitnessSet] = [:]
        for (name, aggregate) in perType where aggregate.witnesses != WitnessSet() {
            result[name] = aggregate.witnesses
        }
        return result
    }

    /// Per-type aggregator — collects inheritance names + provenance
    /// records + decl-kind + gen() presence + witness signatures across
    /// primary decl and any extensions seen in any file.
    private struct TypeAggregate {
        var inheritedNames: [String] = []
        var provenances: [ConformanceMap.Provenance] = []
        /// First primary-decl kind we encountered for this type. Stays
        /// `nil` if only extensions were seen (rare; extensions of types
        /// declared in other modules).
        var typeKind: TypeShape.Kind?
        var hasUserGen: Bool = false
        /// Element-wise OR of witnesses seen in primary decl + every
        /// extension. PRD §5.4 advisory suggestions read from here.
        var witnesses: WitnessSet = WitnessSet()
    }

    /// Bundles file-level scanning context so `recordType` stays under
    /// the function-parameter-count lint.
    private struct RecordingContext {
        let filePath: String
        let converter: SourceLocationConverter
    }

    private static func makeEntries(
        from perType: [String: TypeAggregate]
    ) -> [ConformanceMap.Entry] {
        perType.keys.sorted().map { typeName -> ConformanceMap.Entry in
            let aggregate = perType[typeName]!
            let raw = KnownProtocol.set(from: aggregate.inheritedNames)
            // Default to `.struct` if we only saw extensions and never a
            // primary decl. The strategist falls through to `.todo`
            // anyway in that case.
            let kind = aggregate.typeKind ?? .struct
            let shape = TypeShape(
                name: typeName,
                kind: kind,
                inheritedTypes: aggregate.inheritedNames,
                hasUserGen: aggregate.hasUserGen
            )
            return ConformanceMap.Entry(
                typeName: typeName,
                conformances: KnownProtocol.mostSpecific(in: raw),
                provenances: aggregate.provenances.sorted(),
                derivationStrategy: DerivationStrategist.strategy(for: shape)
            )
        }
    }

    private static func accumulate(
        statement: CodeBlockItemSyntax.Item,
        context: RecordingContext,
        into perType: inout [String: TypeAggregate]
    ) {
        if let primary = primaryDecl(from: statement) {
            record(
                RecordRequest(
                    name: primary.name,
                    inheritance: primary.inheritance,
                    node: primary.node,
                    kind: .primary,
                    typeKind: primary.kind,
                    hasUserGen: primary.hasUserGen,
                    witnesses: primary.witnesses
                ),
                context: context,
                into: &perType
            )
            return
        }
        guard let extensionDecl = statement.as(ExtensionDeclSyntax.self) else { return }
        // Skip conditional conformances (`extension Foo: Equatable where T: ...`)
        // — they're not unconditional, so emitting an unconditional check
        // would be wrong. PRD §4.4 generic conformances handle the bound
        // case via an explicit @LawGenerator(bindings:) annotation, M3 scope.
        guard extensionDecl.genericWhereClause == nil else { return }
        guard let typeName = topLevelExtendedTypeName(of: extensionDecl) else { return }
        record(
            RecordRequest(
                name: typeName,
                inheritance: extensionDecl.inheritanceClause,
                node: Syntax(extensionDecl),
                kind: .extension,
                typeKind: nil,  // extension doesn't redefine the type kind
                hasUserGen: hasGenMethod(in: extensionDecl.memberBlock),
                witnesses: WitnessFinder.find(in: extensionDecl.memberBlock)
            ),
            context: context,
            into: &perType
        )
    }

    /// Unifies the four type-decl shapes a peer macro / scanner can see —
    /// keeps `accumulate` free of repeated `if let` ladders.
    private struct PrimaryDecl {
        let name: String
        let kind: TypeShape.Kind
        let inheritance: InheritanceClauseSyntax?
        let node: Syntax
        let hasUserGen: Bool
        let witnesses: WitnessSet
    }

    private static func primaryDecl(
        from statement: CodeBlockItemSyntax.Item
    ) -> PrimaryDecl? {
        if let decl = statement.as(StructDeclSyntax.self) {
            return PrimaryDecl(
                name: decl.name.text,
                kind: .struct,
                inheritance: decl.inheritanceClause,
                node: Syntax(decl),
                hasUserGen: hasGenMethod(in: decl.memberBlock),
                witnesses: WitnessFinder.find(in: decl.memberBlock)
            )
        }
        if let decl = statement.as(ClassDeclSyntax.self) {
            return PrimaryDecl(
                name: decl.name.text,
                kind: .class,
                inheritance: decl.inheritanceClause,
                node: Syntax(decl),
                hasUserGen: hasGenMethod(in: decl.memberBlock),
                witnesses: WitnessFinder.find(in: decl.memberBlock)
            )
        }
        if let decl = statement.as(EnumDeclSyntax.self) {
            return PrimaryDecl(
                name: decl.name.text,
                kind: .enum,
                inheritance: decl.inheritanceClause,
                node: Syntax(decl),
                hasUserGen: hasGenMethod(in: decl.memberBlock),
                witnesses: WitnessFinder.find(in: decl.memberBlock)
            )
        }
        if let decl = statement.as(ActorDeclSyntax.self) {
            return PrimaryDecl(
                name: decl.name.text,
                kind: .actor,
                inheritance: decl.inheritanceClause,
                node: Syntax(decl),
                hasUserGen: hasGenMethod(in: decl.memberBlock),
                witnesses: WitnessFinder.find(in: decl.memberBlock)
            )
        }
        return nil
    }

    /// True when `memberBlock` declares a `static func gen()` method.
    /// The plugin sees the whole module so this catches gen() defined in
    /// the primary body OR in any extension.
    private static func hasGenMethod(in memberBlock: MemberBlockSyntax) -> Bool {
        for member in memberBlock.members {
            guard let funcDecl = member.decl.as(FunctionDeclSyntax.self) else { continue }
            guard funcDecl.name.text == "gen" else { continue }
            let isStatic = funcDecl.modifiers.contains { mod in
                mod.name.tokenKind == .keyword(.static)
            }
            if isStatic { return true }
        }
        return false
    }

    /// Single-record-call payload — keeps `record` under the
    /// function-parameter-count lint.
    private struct RecordRequest {
        let name: String
        let inheritance: InheritanceClauseSyntax?
        let node: Syntax
        let kind: ConformanceMap.ProvenanceKind
        let typeKind: TypeShape.Kind?
        let hasUserGen: Bool
        let witnesses: WitnessSet
    }

    private static func record(
        _ request: RecordRequest,
        context: RecordingContext,
        into perType: inout [String: TypeAggregate]
    ) {
        var aggregate = perType[request.name] ?? TypeAggregate()
        if let inheritance = request.inheritance {
            for inheritedType in inheritance.inheritedTypes {
                aggregate.inheritedNames.append(inheritedType.type.trimmedDescription)
            }
        }
        let location = request.node.startLocation(converter: context.converter)
        aggregate.provenances.append(ConformanceMap.Provenance(
            filePath: context.filePath,
            line: location.line,
            kind: request.kind
        ))
        // Set typeKind from the primary decl, never from an extension.
        if let primaryKind = request.typeKind {
            aggregate.typeKind = primaryKind
        }
        // hasUserGen latches once true — gen() seen anywhere wins.
        if request.hasUserGen { aggregate.hasUserGen = true }
        aggregate.witnesses.merge(request.witnesses)
        perType[request.name] = aggregate
    }

    /// Extension extends `Foo` or `Module.Foo` — return the leaf identifier.
    /// Nested-type extensions (`extension Outer.Inner`) are M2+ scope.
    private static func topLevelExtendedTypeName(of extensionDecl: ExtensionDeclSyntax) -> String? {
        let typeText = extensionDecl.extendedType.trimmedDescription
        return typeText.split(separator: ".").last.map(String.init)
    }
}
