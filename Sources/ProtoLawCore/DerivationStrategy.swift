/// Generator-derivation strategy for a single type — the result of
/// applying PRD §5.7's priority order to a syntax-agnostic `TypeShape`.
///
/// The macro and the discovery plugin both call `DerivationStrategist`
/// with their own `TypeShape` (built from SwiftSyntax in each case) and
/// emit identical generator-reference text from the returned strategy.
package enum DerivationStrategy: Sendable, Equatable {
    /// User explicitly defines `<TypeName>.gen()`. M1's convention; the
    /// emitter just references `<TypeName>.gen()` and the compiler resolves.
    case userGen

    /// `enum T: CaseIterable` — emit `Gen<T>.element(of: T.allCases)`.
    case caseIterable

    /// `enum T: <RawType>` where `RawType` is a stdlib type with a known
    /// generator (Int, String, Bool, …). The emitter lifts the raw-value
    /// generator through `T.init(rawValue:)` with a `compactMap` to drop
    /// `nil`s for sparse raw spaces.
    case rawRepresentable(RawType)

    /// No strategy matched. The emitter produces a deliberate compile
    /// error pointing at where the user should provide `gen()` or annotate.
    /// `reason` carries a human-readable diagnostic surfaced as a macro
    /// warning alongside the compile error (PRD §5.7 telemetry).
    case todo(reason: String)
}

/// Recognized stdlib raw types for `RawRepresentable` derivation. Each
/// case maps to a generator the emitter can spell out inline.
package enum RawType: String, Sendable, Equatable, CaseIterable {
    case int = "Int"
    case string = "String"
    case bool = "Bool"
    case double = "Double"
    case float = "Float"
    case int8 = "Int8"
    case int16 = "Int16"
    case int32 = "Int32"
    case int64 = "Int64"
    case uint = "UInt"
    case uint8 = "UInt8"
    case uint16 = "UInt16"
    case uint32 = "UInt32"
    case uint64 = "UInt64"

    package init?(typeName: String) {
        guard let match = RawType.allCases.first(where: { $0.rawValue == typeName }) else {
            return nil
        }
        self = match
    }

    /// `swift-property-based` generator factory expression for this raw
    /// type. The emitter inlines this into the lifted `compactMap`. Names
    /// match `Gen+Int.swift` / `Gen+Float.swift` / `Gen.swift` / `Gen+String.swift`
    /// in upstream `swift-property-based` 1.2.x.
    package var generatorExpression: String {
        switch self {
        case .int: return "Gen<Int>.int()"
        case .string: return "Gen<Character>.letterOrNumber.string(of: 0...8)"
        case .bool: return "Gen<Bool>.bool()"
        case .double: return "Gen<Double>.double(in: -1_000_000...1_000_000)"
        case .float: return "Gen<Float>.float(in: -1_000_000...1_000_000)"
        case .int8: return "Gen<Int8>.int8()"
        case .int16: return "Gen<Int16>.int16()"
        case .int32: return "Gen<Int32>.int32()"
        case .int64: return "Gen<Int64>.int64()"
        case .uint: return "Gen<UInt>.uint()"
        case .uint8: return "Gen<UInt8>.uint8()"
        case .uint16: return "Gen<UInt16>.uint16()"
        case .uint32: return "Gen<UInt32>.uint32()"
        case .uint64: return "Gen<UInt64>.uint64()"
        }
    }
}

/// Syntax-agnostic shape of a type declaration — built from SwiftSyntax
/// by the macro impl and the discovery plugin separately, consumed by
/// `DerivationStrategist` to choose a strategy.
package struct TypeShape: Sendable, Equatable {
    package enum Kind: String, Sendable, Equatable {
        case `struct`, `class`, `enum`, `actor`
    }

    package let name: String
    package let kind: Kind
    /// Inheritance-clause type names verbatim, in source order. Used to
    /// detect `CaseIterable`, `RawRepresentable` raw types, and (in
    /// future M3.5) member-conformance scanning.
    package let inheritedTypes: [String]
    /// Whether the user explicitly provides a `gen()` static method on
    /// the type or via an extension in the same file. The macro/plugin
    /// determines this from the surrounding source; the strategist
    /// honors it as the highest-priority strategy (Strategy A from
    /// PRD §5.7).
    package let hasUserGen: Bool

    package init(
        name: String,
        kind: Kind,
        inheritedTypes: [String],
        hasUserGen: Bool
    ) {
        self.name = name
        self.kind = kind
        self.inheritedTypes = inheritedTypes
        self.hasUserGen = hasUserGen
    }
}

/// Pure-logic strategist. Consumes a `TypeShape`, returns a
/// `DerivationStrategy`. No SwiftSyntax dependency — the syntax-to-shape
/// conversion lives in each consumer (macro impl, discovery tool).
package enum DerivationStrategist {

    package static func strategy(for shape: TypeShape) -> DerivationStrategy {
        // Priority order from PRD §5.7. Strategy A — explicit user-provided
        // `gen()` — wins unconditionally. Users who want a derived
        // generator simply don't define `gen()`.
        if shape.hasUserGen {
            return .userGen
        }
        if shape.kind == .enum, shape.inheritedTypes.contains("CaseIterable") {
            return .caseIterable
        }
        if shape.kind == .enum, let rawType = rawType(in: shape.inheritedTypes) {
            return .rawRepresentable(rawType)
        }
        return .todo(reason: todoReason(for: shape))
    }

    /// First inherited type whose name matches a recognized stdlib raw
    /// type. `nil` if none — the type is not a `RawRepresentable` enum
    /// the strategist knows how to derive.
    private static func rawType(in inheritedTypes: [String]) -> RawType? {
        for name in inheritedTypes {
            if let match = RawType(typeName: name) {
                return match
            }
        }
        return nil
    }

    /// Human-readable explanation for the macro's `.todo` warning so the
    /// compile error doesn't surface in isolation.
    private static func todoReason(for shape: TypeShape) -> String {
        switch shape.kind {
        case .enum:
            return "Cannot derive a generator for `\(shape.name)`: not "
                + "`CaseIterable` and no recognized stdlib raw type. Provide "
                + "`static func gen() -> Generator<\(shape.name), some "
                + "SendableSequenceType>` or add `: CaseIterable`."
        case .struct, .class, .actor:
            return "Cannot derive a generator for `\(shape.name)`: memberwise "
                + "derivation isn't supported in M3 (deferred). Provide "
                + "`static func gen() -> Generator<\(shape.name), some "
                + "SendableSequenceType>`."
        }
    }
}
