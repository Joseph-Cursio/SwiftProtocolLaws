import SwiftDiagnostics

/// Diagnostic messages emitted by `@ProtoLawSuite` expansion. Each case
/// has a stable `MessageID.id` so users can suppress per-rule via
/// upstream tooling.
/// Diagnostic identity. The dynamic-message variant
/// `cannotDeriveGenerator(_:)` carries the strategist's reason verbatim
/// so the user sees the same text the discovery plugin would print.
internal enum ProtoLawDiagnostic: DiagnosticMessage {
    /// Macro applied to a non-type declaration (function, property,
    /// extension, etc.). Compilers usually reject the attachment before
    /// the macro runs, but we surface a clear message for the cases
    /// where the attribute slips through.
    case nonTypeDecl

    /// The decoratee conforms to no recognized stdlib protocol — nothing
    /// to emit.
    case noKnownConformance

    /// Generator derivation fell through to `.todo` — the macro will emit
    /// `<TypeName>.gen()` as a placeholder reference, which produces a
    /// compile error pointing at the missing symbol. PRD §5.7 telemetry
    /// requirement: surface which strategy was attempted and why.
    case cannotDeriveGenerator(reason: String)

    var message: String {
        switch self {
        case .nonTypeDecl:
            return "@ProtoLawSuite must decorate a struct, class, enum, or actor."
        case .noKnownConformance:
            return "Type has no recognized stdlib protocol conformance — no "
                + "law checks emitted. Recognized protocols: Equatable, "
                + "Hashable, Comparable, Codable, Sequence, Collection, "
                + "SetAlgebra. Conformances declared via extensions outside "
                + "the type's primary declaration aren't visible to the macro "
                + "(it sees only the decoratee's syntax); upcoming whole-module "
                + "discovery (PRD §5.3) handles those cases."
        case .cannotDeriveGenerator(let reason):
            return reason
        }
    }

    var diagnosticID: MessageID {
        let id: String
        switch self {
        case .nonTypeDecl: id = "nonTypeDecl"
        case .noKnownConformance: id = "noKnownConformance"
        case .cannotDeriveGenerator: id = "cannotDeriveGenerator"
        }
        return MessageID(domain: "ProtoLawMacro", id: id)
    }

    var severity: DiagnosticSeverity {
        switch self {
        case .nonTypeDecl: return .error
        case .noKnownConformance, .cannotDeriveGenerator: return .warning
        }
    }
}
