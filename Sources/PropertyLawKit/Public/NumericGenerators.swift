import PropertyBased

extension Gen where Value: FixedWidthInteger & SignedInteger & Sendable {
    /// Magnitude-bounded generator suitable for protocol-law checks that
    /// involve three-way multiplication or distributivity (`x * (y + z)`).
    ///
    /// Picks a per-type bound `2^(bitWidth / 4)` so cubes stay safely inside
    /// `T.max` — e.g. bound `4` for `Int8` (4³ = 64 < 127), `16` for `Int16`,
    /// `256` for `Int32`, `65_536` for `Int` / `Int64`. Samples in
    /// `-bound ... bound`.
    ///
    /// Use this when calling `checkNumericPropertyLaws` /
    /// `checkBinaryIntegerPropertyLaws` / `checkSignedIntegerPropertyLaws`
    /// against `Int` / `Int32` / `Int64` — the unbounded `Gen<Int>.int()`
    /// default produces values that overflow under triple multiplication on
    /// most random samples, masking real signal in spurious trap-time noise.
    public static func boundedForArithmetic() -> Generator<Value, Shrink.Integer<Value>> {
        let bound = Value(1) << (Value.bitWidth / 4)
        return value(in: -bound ... bound)
    }
}

extension Gen where Value: FixedWidthInteger & UnsignedInteger & Sendable {
    /// Magnitude-bounded generator suitable for protocol-law checks that
    /// involve three-way multiplication or distributivity. Samples in
    /// `0 ... 2^(bitWidth / 4)` — e.g. `0...4` for `UInt8`, `0...256` for
    /// `UInt32`, `0...65_536` for `UInt` / `UInt64`. See the SignedInteger
    /// overload for rationale.
    public static func boundedForArithmetic() -> Generator<Value, Shrink.Integer<Value>> {
        let bound = Value(1) << (Value.bitWidth / 4)
        return value(in: Value.zero ... bound)
    }
}

extension Gen where Value == Double {
    /// `Double` generator that injects `Self.nan` on roughly 1 of every 20
    /// trials, with the rest in `-1e6 ... 1e6` finite range.
    ///
    /// Use with `checkFloatingPointPropertyLaws(..., options:
    /// LawCheckOptions(allowNaN: true))` when you want the always-on laws
    /// to also exercise their NaN-skip guards. The NaN-domain laws
    /// (`nanInequality`, `nanPropagates*`, etc.) construct `Self.nan`
    /// internally and don't require a NaN-producing generator — but having
    /// NaN samples in the always-on laws helps catch broken `isNaN` /
    /// `isFinite` predicates on custom FloatingPoint conformers.
    public static func doubleWithNaN() -> Generator<Double, some SendableSequenceType> {
        Gen<Int>.int(in: 0 ..< 20)
            .map { tag -> Double in
                if tag == 0 { return Double.nan }
                return Double.random(in: -1_000_000.0 ... 1_000_000.0)
            }
    }
}

extension Gen where Value == Float {
    /// `Float` generator that injects `Self.nan` on roughly 1 of every 20
    /// trials, with the rest in `-1e6 ... 1e6` finite range. See the
    /// `Double` overload for rationale.
    public static func floatWithNaN() -> Generator<Float, some SendableSequenceType> {
        Gen<Int>.int(in: 0 ..< 20)
            .map { tag -> Float in
                if tag == 0 { return Float.nan }
                return Float.random(in: -1_000_000.0 ... 1_000_000.0)
            }
    }
}
