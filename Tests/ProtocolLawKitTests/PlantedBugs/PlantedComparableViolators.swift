import PropertyBased

/// Violates Comparable.antisymmetry: `<` orders by `bucket` while `==`
/// distinguishes by `value`. Two values with the same bucket but different
/// values satisfy `x <= y && y <= x` (because both `<` checks return false)
/// without satisfying `x == y`. Probability per trial ≈ 0.5 × 0.9.
struct BucketedOrder: Comparable, Sendable, CustomStringConvertible {
    let bucket: Int
    let value: Int

    static func == (lhs: BucketedOrder, rhs: BucketedOrder) -> Bool {
        lhs.value == rhs.value
    }

    static func < (lhs: BucketedOrder, rhs: BucketedOrder) -> Bool {
        lhs.bucket < rhs.bucket
    }

    var description: String { "B\(bucket)(\(value))" }
}

extension Gen where Value == BucketedOrder {
    static func bucketedOrder() -> Generator<BucketedOrder, some SendableSequenceType> {
        zip(Gen<Int>.int(in: 0...1), Gen<Int>.int(in: 0...10))
            .map { bucket, value in BucketedOrder(bucket: bucket, value: value) }
    }
}

/// Violates Comparable.operatorConsistency: `<` always returns true, which
/// makes the derived `<=` (`!(rhs < lhs)`) always false. So `x < y && !(x <= y)`
/// holds for every pair — internally inconsistent operator surface even
/// though `<=` itself is the protocol's default.
struct AlwaysLessThan: Comparable, Sendable, CustomStringConvertible {
    let value: Int

    static func == (lhs: AlwaysLessThan, rhs: AlwaysLessThan) -> Bool {
        lhs.value == rhs.value
    }

    static func < (lhs: AlwaysLessThan, rhs: AlwaysLessThan) -> Bool {
        true
    }

    var description: String { "ALT(\(value))" }
}

extension Gen where Value == AlwaysLessThan {
    static func alwaysLessThan() -> Generator<AlwaysLessThan, some SendableSequenceType> {
        Gen<Int>.int(in: 0...20).map { AlwaysLessThan(value: $0) }
    }
}

/// Violates Comparable.transitivity (of `<=`): a rock-paper-scissors cycle
/// over three buckets makes `a <= b && b <= c` true while `a <= c` is false.
struct CyclicOrder: Comparable, Sendable, CustomStringConvertible {
    let bucket: Int // 0, 1, or 2

    static func == (lhs: CyclicOrder, rhs: CyclicOrder) -> Bool {
        lhs.bucket == rhs.bucket
    }

    static func < (lhs: CyclicOrder, rhs: CyclicOrder) -> Bool {
        // 0 < 1, 1 < 2, 2 < 0 (cycle)
        let l = lhs.bucket, r = rhs.bucket
        return (l == 0 && r == 1) || (l == 1 && r == 2) || (l == 2 && r == 0)
    }

    var description: String { "C\(bucket)" }
}

extension Gen where Value == CyclicOrder {
    static func cyclicOrder() -> Generator<CyclicOrder, some SendableSequenceType> {
        Gen<Int>.int(in: 0...2).map { CyclicOrder(bucket: $0) }
    }
}
