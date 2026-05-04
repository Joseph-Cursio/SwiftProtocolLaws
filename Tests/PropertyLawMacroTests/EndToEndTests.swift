import Testing
import PropertyBased
import PropertyLawKit
import PropertyLawMacro

/// End-to-end smoke for `@PropertyLawSuite`: a real type with stdlib
/// conformances and recognized raw-type stored properties gets a peer test
/// suite emitted by the macro, and the generated `@Test func`s actually
/// run against PropertyLawKit — not just stringly-matched in
/// `assertMacroExpansion`.
///
/// Derivation strategy in play here: PRD §5.7 Strategy 3
/// (memberwise-Arbitrary). No user `gen()` exists; the macro inspects the
/// stored properties (`easting: Int`, `northing: Int`), confirms each
/// resolves to a recognized `RawType`, and emits
/// `zip(Gen<Int>.int(), Gen<Int>.int()).map { EndToEndCoordinate(...) }`
/// at the `using:` argument site. Compiling this file is the proof that
/// memberwise derivation produces valid code; the generated `@Test`s
/// running clean is the proof it produces a generator that exercises the
/// laws.
@PropertyLawSuite
struct EndToEndCoordinate: Equatable, Hashable, Sendable, CustomStringConvertible {
    let easting: Int
    let northing: Int

    static func == (lhs: EndToEndCoordinate, rhs: EndToEndCoordinate) -> Bool {
        lhs.easting == rhs.easting && lhs.northing == rhs.northing
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(easting)
        hasher.combine(northing)
    }

    var description: String { "(\(easting), \(northing))" }
}
