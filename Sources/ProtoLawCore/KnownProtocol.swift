/// Recognized stdlib protocols that ProtocolLawKit covers (PRD §4.3 v1
/// scope). The macro and the discovery plugin both emit
/// `checkXxxProtocolLaws` calls only for these.
///
/// `package`-visibility because both `ProtoLawMacroImpl` and
/// `ProtoLawDiscoveryTool` consume this enum and they need a shared source
/// of truth — but it's an implementation detail, not a public API of the
/// shipped libraries.
package enum KnownProtocol: String, CaseIterable, Hashable, Sendable {
    case equatable
    case hashable
    case comparable
    case codable
    case iteratorProtocol
    case sequence
    case collection
    case setAlgebra
    case strideable
    case rawRepresentable
    case losslessStringConvertible

    /// Maps a single inheritance-clause type name to a `KnownProtocol`.
    /// `Encodable`/`Decodable` are intentionally absent — only the pair
    /// resolves to `.codable`, handled by `KnownProtocol.set(from:)`.
    package static func from(typeName: String) -> KnownProtocol? {
        typeNameMap[typeName]
    }

    private static let typeNameMap: [String: KnownProtocol] = [
        "Equatable": .equatable,
        "Hashable": .hashable,
        "Comparable": .comparable,
        "Codable": .codable,
        "IteratorProtocol": .iteratorProtocol,
        "Sequence": .sequence,
        "Collection": .collection,
        "SetAlgebra": .setAlgebra,
        "Strideable": .strideable,
        "RawRepresentable": .rawRepresentable,
        "LosslessStringConvertible": .losslessStringConvertible
    ]

    /// Resolve a list of raw inherited-type names into the recognized
    /// `KnownProtocol` set, including the `Encodable + Decodable` →
    /// `.codable` pairing and the `Strideable` ⇒ `Comparable` implication
    /// (Strideable's stdlib definition refines Comparable, so any
    /// Strideable type is by definition Comparable; auto-adding Comparable
    /// lets the macro/plugin emit `checkComparableProtocolLaws` for types
    /// that only spell `: Strideable` in their inheritance clause).
    package static func set(from typeNames: [String]) -> Set<KnownProtocol> {
        var result: Set<KnownProtocol> = []
        var hasEncodable = false
        var hasDecodable = false
        for name in typeNames {
            if let known = from(typeName: name) {
                result.insert(known)
            }
            if name == "Encodable" { hasEncodable = true }
            if name == "Decodable" { hasDecodable = true }
        }
        if hasEncodable && hasDecodable {
            result.insert(.codable)
        }
        if result.contains(.strideable) {
            result.insert(.comparable)
        }
        return result
    }

    /// Protocols whose check functions can't be emitted by the macro / plugin
    /// from inheritance-clause syntax alone. `IteratorProtocol`'s check is
    /// parameterized over a host `Sequence`, and `Strideable`'s requires a
    /// separate `strideGenerator:` over the associated `Stride` type. Both
    /// callers filter these out *before* applying `mostSpecific` so that
    /// subsumed peers (notably `Comparable` for Strideable) survive into the
    /// emit set.
    package static let unemittable: Set<KnownProtocol> = [.iteratorProtocol, .strideable]

    /// Filters `protocols` down to its most-specific members per PRD §4.3
    /// inheritance semantics: when one recognized protocol's check already
    /// runs another's laws via the kit's inheritance chain, the latter is
    /// dropped from the emit set.
    ///
    /// Concretely:
    /// - Hashable subsumes Equatable.
    /// - Comparable subsumes Equatable.
    /// - Strideable subsumes Comparable (and transitively Equatable).
    /// - Collection subsumes Sequence subsumes IteratorProtocol.
    package static func mostSpecific(in protocols: Set<KnownProtocol>) -> Set<KnownProtocol> {
        var result = protocols
        for member in protocols {
            for subsumed in member.subsumedProtocols {
                result.remove(subsumed)
            }
        }
        return result
    }

    private var subsumedProtocols: Set<KnownProtocol> {
        switch self {
        case .hashable, .comparable: return [.equatable]
        case .strideable: return [.comparable]
        case .collection: return [.sequence, .iteratorProtocol]
        case .sequence: return [.iteratorProtocol]
        case .equatable, .codable, .iteratorProtocol, .setAlgebra,
             .rawRepresentable, .losslessStringConvertible: return []
        }
    }

    /// Function-name prefix for the kit's check call. The macro composes the
    /// final identifier as `check<prefixCapitalized>ProtocolLaws`.
    package var checkFunctionName: String {
        switch self {
        case .equatable: return "checkEquatableProtocolLaws"
        case .hashable: return "checkHashableProtocolLaws"
        case .comparable: return "checkComparableProtocolLaws"
        case .codable: return "checkCodableProtocolLaws"
        case .iteratorProtocol: return "checkIteratorProtocolLaws"
        case .sequence: return "checkSequenceProtocolLaws"
        case .collection: return "checkCollectionProtocolLaws"
        case .setAlgebra: return "checkSetAlgebraProtocolLaws"
        case .strideable: return "checkStrideableProtocolLaws"
        case .rawRepresentable: return "checkRawRepresentableProtocolLaws"
        case .losslessStringConvertible: return "checkLosslessStringConvertibleProtocolLaws"
        }
    }

    /// `@Test func` name fragment — `<prefix>_<TypeName>` makes generated
    /// tests greppable in test output.
    package var testNameFragment: String {
        switch self {
        case .equatable: return "equatable"
        case .hashable: return "hashable"
        case .comparable: return "comparable"
        case .codable: return "codable"
        case .iteratorProtocol: return "iteratorProtocol"
        case .sequence: return "sequence"
        case .collection: return "collection"
        case .setAlgebra: return "setAlgebra"
        case .strideable: return "strideable"
        case .rawRepresentable: return "rawRepresentable"
        case .losslessStringConvertible: return "losslessStringConvertible"
        }
    }
}
