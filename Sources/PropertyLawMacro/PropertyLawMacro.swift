@_exported import PropertyLawKit

/// Peer macro that attaches to a type declaration, reads its inheritance
/// clause, and emits a sibling `@Suite` struct of `@Test func` methods —
/// one per recognized stdlib protocol the type conforms to (PRD §4.3).
///
/// The peer-macro shape is required by Swift's macro model: macro
/// implementations see only the syntax of their decoratee, not the
/// surrounding file. PRD §9 Decision 4 already separates whole-module
/// discovery into the upcoming Swift Package Plugin (M2). The PRD's
/// `[Foo.self, Bar.self]`-on-a-test-suite form can't be implemented as
/// a macro for that same reason; it lives on the plugin side.
///
/// Generator-name convention: the macro emits `\(TypeName).gen()` —
/// users define a static `gen()` method on the type (or via an extension
/// in the same module). A missing generator surfaces as a "cannot find
/// `Foo.gen`" compile error, matching PRD §5.7's "compile error beats
/// silent fallthrough" stance. Real generator derivation lands in M3.
///
/// ```swift
/// @PropertyLawSuite
/// struct Foo: Equatable, Hashable {
///     let value: Int
/// }
///
/// extension Foo {
///     static func gen() -> Generator<Foo, some SendableSequenceType> {
///         // ...
///     }
/// }
/// ```
///
/// Expands (as a peer of `Foo`) to:
/// ```swift
/// @Suite struct FooPropertyLawTests {
///     @Test func hashable_Foo() async throws {
///         try await checkHashablePropertyLaws(for: Foo.self, using: Foo.gen())
///     }
/// }
/// ```
@attached(peer, names: suffixed(PropertyLawTests))
public macro PropertyLawSuite() = #externalMacro(
    module: "PropertyLawMacroImpl",
    type: "PropertyLawSuiteMacro"
)

/// Marker peer macro that tags a function as a candidate for PRD §5.5
/// cross-function round-trip discovery and (optionally) groups it with
/// other tagged functions via the `group:` argument.
///
/// `@Discoverable` is read by the M2 discovery plugin's `--advisory`
/// pass: when two `@Discoverable(group: "x")`-tagged functions in the
/// same scope have inverse signatures, the suggester emits a HIGH-
/// confidence round-trip suggestion to stderr even when the function
/// names aren't in the curated naming-pair table. The attribute is a
/// no-op at runtime — the macro emits no peer declarations.
///
/// ```swift
/// struct Codec {
///     @Discoverable(group: "wire")
///     static func toBytes(_ x: Foo) -> Data { ... }
///
///     @Discoverable(group: "wire")
///     static func fromBytes(_ d: Data) -> Foo { ... }
/// }
/// ```
///
/// The discovery tool sees the matching group plus inverse signatures
/// and surfaces the pair, even though `toBytes` / `fromBytes` aren't in
/// the encode/decode-style naming table. Output goes to stderr only;
/// the generated file is unchanged (preserves regeneration-as-diff).
@attached(peer, names: arbitrary)
public macro Discoverable(group: String? = nil) = #externalMacro(
    module: "PropertyLawMacroImpl",
    type: "DiscoverableMacro"
)
