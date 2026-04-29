import PropertyBased

// MARK: - BidirectionalCollection planted bug

/// BidirectionalCollection whose `index(before:)` is a no-op — the index
/// doesn't move backward at all. Violates
/// `BidirectionalCollection.indexBeforeAfterRoundTrip` (and the other two
/// bidirectional laws) because `index(before: index(after: i))` returns
/// `i + 1`, not `i`.
struct StuckIndexBeforeCollection: BidirectionalCollection, Sendable, CustomStringConvertible {
    let storage: [Int]

    var startIndex: Int { 0 }
    var endIndex: Int { storage.count }

    func index(after position: Int) -> Int { position + 1 }
    func index(before position: Int) -> Int { position }  // the bug

    subscript(position: Int) -> Int { storage[position] }

    var description: String { "StuckIndexBefore(\(storage))" }
}

extension Gen where Value == StuckIndexBeforeCollection {
    static func stuckIndexBefore() -> Generator<
        StuckIndexBeforeCollection, some SendableSequenceType
    > {
        Gen<Int>.int(in: 0...10)
            .array(of: 2...4)
            .map { StuckIndexBeforeCollection(storage: $0) }
    }
}

// MARK: - RandomAccessCollection planted bug

/// RandomAccessCollection whose `distance(from:to:)` returns the wrong sign.
/// Forward-walking via `index(after:)` works (inherited from Collection);
/// only the random-access shortcut lies. Violates
/// `RandomAccessCollection.distanceConsistency`.
struct WrongDistanceCollection: RandomAccessCollection, Sendable, CustomStringConvertible {
    let storage: [Int]

    var startIndex: Int { 0 }
    var endIndex: Int { storage.count }

    func index(after position: Int) -> Int { position + 1 }
    func index(before position: Int) -> Int { position - 1 }

    func distance(from start: Int, to end: Int) -> Int {
        // The bug: returns the absolute distance, dropping the sign.
        // For start <= end the answer is correct; for start > end the
        // expected value is negative and the lie surfaces.
        Swift.abs(end - start)
    }

    subscript(position: Int) -> Int { storage[position] }

    var description: String { "WrongDistance(\(storage))" }
}

extension Gen where Value == WrongDistanceCollection {
    static func wrongDistance() -> Generator<
        WrongDistanceCollection, some SendableSequenceType
    > {
        Gen<Int>.int(in: 0...10)
            .array(of: 2...4)
            .map { WrongDistanceCollection(storage: $0) }
    }
}

// MARK: - MutableCollection planted bug

/// MutableCollection whose subscript setter is a no-op. The getter still
/// returns the original element, so `c.swapAt(i, j)` (whose default impl
/// goes through subscript get + set) leaves both elements unchanged.
/// Violates `MutableCollection.swapAtSwapsValues` (but, deceptively, NOT
/// `swapAtInvolution` — a no-op composed with a no-op is identity).
struct NoOpSetterCollection: MutableCollection, Sendable, CustomStringConvertible {
    var storage: [Int]

    var startIndex: Int { 0 }
    var endIndex: Int { storage.count }

    func index(after position: Int) -> Int { position + 1 }

    subscript(position: Int) -> Int {
        get { storage[position] }
        // swiftlint:disable:next unused_setter_value
        set { /* the bug — write is dropped */ }
    }

    var description: String { "NoOpSetter(\(storage))" }
}

extension Gen where Value == NoOpSetterCollection {
    static func noOpSetter() -> Generator<NoOpSetterCollection, some SendableSequenceType> {
        // Pairs of distinct values so a working setter would observably
        // swap them — without distinct values, swapAtSwapsValues passes
        // vacuously even on a broken setter.
        Gen<Int>.int(in: 0...3)
            .array(of: 2...4)
            .map { values -> NoOpSetterCollection in
                var deduped = values
                for offset in deduped.indices {
                    deduped[offset] = offset &* 7 &+ values[offset]
                }
                return NoOpSetterCollection(storage: deduped)
            }
    }
}

// MARK: - RangeReplaceableCollection planted bug

/// RangeReplaceableCollection whose `replaceSubrange(_:with:)` is a no-op.
/// `removeAll()`, `remove(at:)`, `insert(_:at:)` and friends all dispatch
/// through `replaceSubrange` in the default implementations, so all of the
/// kit's RangeReplaceableCollection laws fail. The single-method bug
/// reproduces the typical real-world failure mode of a custom collection
/// where the protocol's one mutating requirement is misimplemented.
struct NoOpReplaceSubrange: RangeReplaceableCollection, Sendable, CustomStringConvertible {
    var storage: [Int]

    init() { self.storage = [] }
    init(storage: [Int]) { self.storage = storage }

    var startIndex: Int { 0 }
    var endIndex: Int { storage.count }

    func index(after position: Int) -> Int { position + 1 }
    subscript(position: Int) -> Int { storage[position] }

    mutating func replaceSubrange<C: Collection>(
        _ subrange: Range<Int>,
        with newElements: C
    ) where C.Element == Int {
        // the bug — no edit applied
    }

    var description: String { "NoOpReplace(\(storage))" }
}

extension Gen where Value == NoOpReplaceSubrange {
    static func noOpReplaceSubrange() -> Generator<
        NoOpReplaceSubrange, some SendableSequenceType
    > {
        Gen<Int>.int(in: 0...10)
            .array(of: 1...4)
            .map { NoOpReplaceSubrange(storage: $0) }
    }
}
