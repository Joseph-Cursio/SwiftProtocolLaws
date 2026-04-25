/// Recognized stdlib protocols that ProtocolLawKit covers (PRD §4.3 v1
/// scope). The macro emits `checkXxxProtocolLaws` calls only for these.
internal enum KnownProtocol: String, CaseIterable, Hashable {
    case equatable
    case hashable
    case comparable
    case codable
    case iteratorProtocol
    case sequence
    case collection
    case setAlgebra

    /// Maps a single inheritance-clause type name to a `KnownProtocol`.
    /// `Encodable`/`Decodable` are intentionally absent — only the pair
    /// resolves to `.codable`, handled by `KnownProtocol.set(from:)`.
    static func from(typeName: String) -> KnownProtocol? {
        switch typeName {
        case "Equatable": return .equatable
        case "Hashable": return .hashable
        case "Comparable": return .comparable
        case "Codable": return .codable
        case "IteratorProtocol": return .iteratorProtocol
        case "Sequence": return .sequence
        case "Collection": return .collection
        case "SetAlgebra": return .setAlgebra
        default: return nil
        }
    }

    /// Resolve a list of raw inherited-type names into the recognized
    /// `KnownProtocol` set, including the `Encodable + Decodable` →
    /// `.codable` pairing.
    static func set(from typeNames: [String]) -> Set<KnownProtocol> {
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
        return result
    }

    /// Filters `protocols` down to its most-specific members per PRD §4.3
    /// inheritance semantics: when one recognized protocol's check already
    /// runs another's laws via the kit's inheritance chain, the latter is
    /// dropped from the emit set.
    ///
    /// Concretely:
    /// - Hashable subsumes Equatable.
    /// - Comparable subsumes Equatable.
    /// - Collection subsumes Sequence subsumes IteratorProtocol.
    static func mostSpecific(in protocols: Set<KnownProtocol>) -> Set<KnownProtocol> {
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
        case .collection: return [.sequence, .iteratorProtocol]
        case .sequence: return [.iteratorProtocol]
        case .equatable, .codable, .iteratorProtocol, .setAlgebra: return []
        }
    }

    /// Function-name prefix for the kit's check call. The macro composes the
    /// final identifier as `check<prefixCapitalized>ProtocolLaws`.
    var checkFunctionName: String {
        switch self {
        case .equatable: return "checkEquatableProtocolLaws"
        case .hashable: return "checkHashableProtocolLaws"
        case .comparable: return "checkComparableProtocolLaws"
        case .codable: return "checkCodableProtocolLaws"
        case .iteratorProtocol: return "checkIteratorProtocolLaws"
        case .sequence: return "checkSequenceProtocolLaws"
        case .collection: return "checkCollectionProtocolLaws"
        case .setAlgebra: return "checkSetAlgebraProtocolLaws"
        }
    }

    /// `@Test func` name fragment — `<prefix>_<TypeName>` makes generated
    /// tests greppable in test output.
    var testNameFragment: String {
        switch self {
        case .equatable: return "equatable"
        case .hashable: return "hashable"
        case .comparable: return "comparable"
        case .codable: return "codable"
        case .iteratorProtocol: return "iteratorProtocol"
        case .sequence: return "sequence"
        case .collection: return "collection"
        case .setAlgebra: return "setAlgebra"
        }
    }
}
