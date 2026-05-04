import PropertyBased

/// Violates `SignedNumeric.negationInvolution` (and as a consequence
/// `additiveInverse` on most samples). `prefix -` doubles-and-flips sign
/// instead of just flipping it, so `-(-x) = 4·x ≠ x` for any non-zero `x`
/// and `x + (-x) = -x ≠ 0`. The inherited Numeric / AdditiveArithmetic
/// laws still hold because `+`, `-`, and `*` forward straight through to
/// `Int`'s correct implementations.
struct BrokenNegationOffByOne: SignedNumeric, Sendable, CustomStringConvertible {
    var value: Int

    init(value: Int) { self.value = value }
    init(integerLiteral value: Int) { self.value = value }
    init?<T: BinaryInteger>(exactly source: T) {
        guard let candidate = Int(exactly: source) else { return nil }
        self.value = candidate
    }

    var magnitude: Int { abs(value) }

    static let zero = BrokenNegationOffByOne(value: 0)

    static func + (lhs: Self, rhs: Self) -> Self { Self(value: lhs.value + rhs.value) }
    static func - (lhs: Self, rhs: Self) -> Self { Self(value: lhs.value - rhs.value) }
    static func * (lhs: Self, rhs: Self) -> Self { Self(value: lhs.value * rhs.value) }
    static func *= (lhs: inout Self, rhs: Self) { lhs = lhs * rhs }

    /// `-x = -2·x.value` (scale-and-flip) so `-(-x) = 4·x.value ≠ x` for
    /// any `x ≠ 0`. A pure off-by-one (`-x = -x.value + 1`) cancels under
    /// involution and would not be caught.
    static prefix func - (operand: Self) -> Self {
        Self(value: -2 * operand.value)
    }

    mutating func negate() {
        self = -self
    }

    var description: String { "BNI(\(value))" }
}

extension Gen where Value == BrokenNegationOffByOne {
    static func brokenNegationOffByOne() -> Generator<BrokenNegationOffByOne, some SendableSequenceType> {
        Gen<Int>.int(in: -10...10).map { BrokenNegationOffByOne(value: $0) }
    }
}
