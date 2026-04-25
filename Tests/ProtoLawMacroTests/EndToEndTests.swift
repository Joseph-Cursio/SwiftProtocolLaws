import Testing
import PropertyBased
import ProtocolLawKit
import ProtoLawMacro

/// End-to-end smoke for `@ProtoLawSuite`: a real type with stdlib
/// conformances + a `gen()` method gets a peer test suite emitted by the
/// macro. The generated `@Test func`s actually run against
/// ProtocolLawKit — not just stringly-matched in `assertMacroExpansion`.
@ProtoLawSuite
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

extension EndToEndCoordinate {
    static func gen() -> Generator<EndToEndCoordinate, some SendableSequenceType> {
        zip(Gen<Int>.int(in: -50...50), Gen<Int>.int(in: -50...50))
            .map { EndToEndCoordinate(easting: $0, northing: $1) }
    }
}
