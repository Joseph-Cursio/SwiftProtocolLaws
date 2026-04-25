@_exported import ProtocolLawKit

/// Member macro that detects each named type's stdlib protocol conformances
/// (PRD §4.3) by scanning the same source file, then expands to `@Test func`
/// methods calling the appropriate `checkXxxProtocolLaws` for each match.
///
/// Cross-file types aren't supported here by design — macros are file-local
/// (PRD §9 Decision 4); whole-module scanning ships in M2 as a Swift Package
/// Plugin. For each named type that *isn't* in the surrounding file, the
/// macro emits an error diagnostic suggesting the plugin.
///
/// Generators are looked up by convention as `Self.<typeName lowerCamel>Gen`.
/// The macro doesn't validate this at expansion time — a missing generator
/// surfaces as a "cannot find Self.fooGen" compile error in the expansion,
/// matching PRD §5.7's "compile error beats silent fallthrough" stance.
/// Real generator derivation lands in M3.
///
/// The macro adds **only** test methods. The user retains control of the
/// surrounding `@Suite` annotation:
///
/// ```swift
/// @Suite
/// @ProtoLawSuite(types: [Foo.self, Bar.self])
/// struct ConformanceLaws {
///     static let fooGen = Gen.foo()
///     static let barGen = Gen.bar()
/// }
/// ```
@attached(member, names: arbitrary)
public macro ProtoLawSuite(types: [Any.Type]) = #externalMacro(
    module: "ProtoLawMacroImpl",
    type: "ProtoLawSuiteMacro"
)
