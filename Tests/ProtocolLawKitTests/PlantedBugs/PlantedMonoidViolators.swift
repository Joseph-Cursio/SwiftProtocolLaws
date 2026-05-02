import PropertyBased
import ProtocolLawKit

/// Violates `Monoid.combineLeftIdentity`. `combine(.identity, x)` returns
/// `Bumped(x.value + 1)` instead of `x`. The right-identity case still
/// holds, and associativity holds because `combine` is otherwise
/// commutative+associative integer addition.
struct BadLeftIdentity: Monoid, Equatable, Sendable, CustomStringConvertible {
    let value: Int

    static let identity = BadLeftIdentity(value: 0)

    static func combine(_ lhs: BadLeftIdentity, _ rhs: BadLeftIdentity) -> BadLeftIdentity {
        if lhs.value == 0 && rhs.value != 0 {
            return BadLeftIdentity(value: rhs.value + 1)
        }
        return BadLeftIdentity(value: lhs.value + rhs.value)
    }

    var description: String { "BLI(\(value))" }
}

extension Gen where Value == BadLeftIdentity {
    static func badLeftIdentity() -> Generator<BadLeftIdentity, some SendableSequenceType> {
        Gen<Int>.int(in: 1...50).map { BadLeftIdentity(value: $0) }
    }
}

/// Violates `Monoid.combineRightIdentity`. Mirror image of `BadLeftIdentity`
/// — the right-identity short-circuit bumps by 1 instead of returning
/// `lhs`. Left identity still holds.
struct BadRightIdentity: Monoid, Equatable, Sendable, CustomStringConvertible {
    let value: Int

    static let identity = BadRightIdentity(value: 0)

    static func combine(_ lhs: BadRightIdentity, _ rhs: BadRightIdentity) -> BadRightIdentity {
        if rhs.value == 0 && lhs.value != 0 {
            return BadRightIdentity(value: lhs.value + 1)
        }
        return BadRightIdentity(value: lhs.value + rhs.value)
    }

    var description: String { "BRI(\(value))" }
}

extension Gen where Value == BadRightIdentity {
    static func badRightIdentity() -> Generator<BadRightIdentity, some SendableSequenceType> {
        Gen<Int>.int(in: 1...50).map { BadRightIdentity(value: $0) }
    }
}
