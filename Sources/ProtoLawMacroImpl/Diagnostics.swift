import SwiftDiagnostics

/// Diagnostic messages emitted by `@ProtoLawSuite` expansion. Each case
/// has a stable `MessageID.id` so users can suppress per-rule via
/// upstream tooling.
internal enum ProtoLawDiagnostic: String, DiagnosticMessage {
    /// The macro's `types:` argument couldn't be parsed as
    /// `[Identifier.self, ...]`.
    case malformedArgs

    /// A `types:` element isn't a `Foo.self` literal — generics, type-of
    /// expressions, and aliases aren't supported in M1.
    case malformedTypeElement

    /// Named type's declaration isn't in the same source file. Cross-file
    /// scanning is the M2 Discovery plugin (PRD §5.3).
    case typeNotInFile

    /// Type found but conforms to no recognized stdlib protocol — nothing
    /// to emit.
    case noKnownConformance

    var message: String {
        switch self {
        case .malformedArgs:
            return "@ProtoLawSuite expects `types: [SomeType.self, ...]`. "
                + "Pass an array literal of metatype expressions."
        case .malformedTypeElement:
            return "Each element of `types:` must be a metatype literal "
                + "(e.g. `Foo.self`). Generic parameters, `type(of:)`, and "
                + "type aliases aren't supported in M1."
        case .typeNotInFile:
            return "Type not declared in this file. @ProtoLawSuite scans the "
                + "current file for declarations and extensions; cross-file "
                + "discovery is the upcoming Swift Package Plugin (PRD §5.3)."
        case .noKnownConformance:
            return "Type has no recognized stdlib protocol conformance — no "
                + "law checks emitted. Recognized protocols: Equatable, "
                + "Hashable, Comparable, Codable, Sequence, Collection, "
                + "SetAlgebra."
        }
    }

    var diagnosticID: MessageID {
        MessageID(domain: "ProtoLawMacro", id: rawValue)
    }

    var severity: DiagnosticSeverity {
        switch self {
        case .malformedArgs, .malformedTypeElement, .typeNotInFile:
            return .error
        case .noKnownConformance:
            return .warning
        }
    }
}
