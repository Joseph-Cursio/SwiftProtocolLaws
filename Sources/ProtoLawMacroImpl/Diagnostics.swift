import SwiftDiagnostics

/// Diagnostic messages emitted by `@ProtoLawSuite` expansion. Each case
/// has a stable `MessageID.id` so users can suppress per-rule via
/// upstream tooling.
internal enum ProtoLawDiagnostic: String, DiagnosticMessage {
    /// Macro applied to a non-type declaration (function, property,
    /// extension, etc.). Compilers usually reject the attachment before
    /// the macro runs, but we surface a clear message for the cases
    /// where the attribute slips through.
    case nonTypeDecl

    /// The decoratee conforms to no recognized stdlib protocol — nothing
    /// to emit.
    case noKnownConformance

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
        }
    }

    var diagnosticID: MessageID {
        MessageID(domain: "ProtoLawMacro", id: rawValue)
    }

    var severity: DiagnosticSeverity {
        switch self {
        case .nonTypeDecl: return .error
        case .noKnownConformance: return .warning
        }
    }
}
