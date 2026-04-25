import SwiftCompilerPlugin
import SwiftSyntaxMacros

/// Compiler-plugin entry point. Registers every macro implementation
/// the user-facing `ProtoLawMacro` module forwards to.
@main
struct ProtoLawMacroPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        ProtoLawSuiteMacro.self
    ]
}
