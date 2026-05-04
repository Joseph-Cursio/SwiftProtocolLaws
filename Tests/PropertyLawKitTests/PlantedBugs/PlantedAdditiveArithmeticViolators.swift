import PropertyBased

/// Violates `AdditiveArithmetic.zeroAdditiveIdentity`. `+ .zero` adds 1
/// instead of returning `self`. The other four laws still hold because `+`
/// is otherwise consistent with `-` and `static var zero`.
struct BadZeroIdentity: AdditiveArithmetic, Equatable, Sendable, CustomStringConvertible {
    let value: Int

    static let zero = BadZeroIdentity(value: 0)

    static func + (lhs: BadZeroIdentity, rhs: BadZeroIdentity) -> BadZeroIdentity {
        if rhs.value == 0 { return BadZeroIdentity(value: lhs.value + 1) }
        if lhs.value == 0 { return BadZeroIdentity(value: rhs.value + 1) }
        return BadZeroIdentity(value: lhs.value + rhs.value)
    }

    static func - (lhs: BadZeroIdentity, rhs: BadZeroIdentity) -> BadZeroIdentity {
        BadZeroIdentity(value: lhs.value - rhs.value)
    }

    var description: String { "BZI(\(value))" }
}

extension Gen where Value == BadZeroIdentity {
    static func badZeroIdentity() -> Generator<BadZeroIdentity, some SendableSequenceType> {
        Gen<Int>.int(in: -50...50).map { BadZeroIdentity(value: $0) }
    }
}

/// Violates `AdditiveArithmetic.additionAssociativity` (and as a side-effect
/// the subtraction-inverse law on certain triples). `+` short-circuits when
/// either operand is the running max, producing a value that's path-dependent
/// across `(x + y) + z` vs `x + (y + z)`.
struct NonAssociativeAddition: AdditiveArithmetic, Equatable, Sendable, CustomStringConvertible {
    let value: Int

    static let zero = NonAssociativeAddition(value: 0)

    static func + (
        lhs: NonAssociativeAddition,
        rhs: NonAssociativeAddition
    ) -> NonAssociativeAddition {
        // Floor-divide by 2 every time both operands are non-zero, which
        // associativity would require to commute with the regrouping.
        let raw = lhs.value + rhs.value
        if lhs.value != 0 && rhs.value != 0 {
            return NonAssociativeAddition(value: raw / 2)
        }
        return NonAssociativeAddition(value: raw)
    }

    static func - (
        lhs: NonAssociativeAddition,
        rhs: NonAssociativeAddition
    ) -> NonAssociativeAddition {
        NonAssociativeAddition(value: lhs.value - rhs.value)
    }

    var description: String { "NAA(\(value))" }
}

extension Gen where Value == NonAssociativeAddition {
    static func nonAssociativeAddition() -> Generator<NonAssociativeAddition, some SendableSequenceType> {
        Gen<Int>.int(in: -50...50).map { NonAssociativeAddition(value: $0) }
    }
}
