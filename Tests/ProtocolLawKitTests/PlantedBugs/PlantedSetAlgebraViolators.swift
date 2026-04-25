import PropertyBased

/// SetAlgebra wrapper whose `union(_:)` returns `self` unchanged, ignoring
/// the right-hand side. Idempotence and emptyIdentity vacuously pass
/// (`x.union(x)` and `x.union(empty)` both return `x`), but commutativity
/// fails: `a.union(b) = a`, `b.union(a) = b`, and the two differ when
/// `a != b`.
struct LeftBiasedUnion: SetAlgebra, Equatable, Sendable, CustomStringConvertible {
    typealias Element = Int

    var underlying: Set<Int>

    init() { self.underlying = [] }
    init(_ elements: Set<Int>) { self.underlying = elements }

    func contains(_ member: Int) -> Bool { underlying.contains(member) }

    // The bug: union returns self instead of merging the two operands.
    func union(_ other: LeftBiasedUnion) -> LeftBiasedUnion { self }

    func intersection(_ other: LeftBiasedUnion) -> LeftBiasedUnion {
        LeftBiasedUnion(underlying.intersection(other.underlying))
    }
    func symmetricDifference(_ other: LeftBiasedUnion) -> LeftBiasedUnion {
        LeftBiasedUnion(underlying.symmetricDifference(other.underlying))
    }

    mutating func formUnion(_ other: LeftBiasedUnion) {
        underlying.formUnion(other.underlying)
    }
    mutating func formIntersection(_ other: LeftBiasedUnion) {
        underlying.formIntersection(other.underlying)
    }
    mutating func formSymmetricDifference(_ other: LeftBiasedUnion) {
        underlying.formSymmetricDifference(other.underlying)
    }

    @discardableResult
    mutating func insert(
        _ newMember: Int
    ) -> (inserted: Bool, memberAfterInsert: Int) {
        underlying.insert(newMember)
    }
    @discardableResult
    mutating func remove(_ member: Int) -> Int? { underlying.remove(member) }
    @discardableResult
    mutating func update(with newMember: Int) -> Int? {
        underlying.update(with: newMember)
    }

    static func == (lhs: LeftBiasedUnion, rhs: LeftBiasedUnion) -> Bool {
        lhs.underlying == rhs.underlying
    }

    var description: String {
        "LBU(\(underlying.sorted()))"
    }
}

extension Gen where Value == LeftBiasedUnion {
    static func leftBiasedUnion() -> Generator<LeftBiasedUnion, some SendableSequenceType> {
        Gen<Int>.int(in: 0...20)
            .array(of: 0...4)
            .map { LeftBiasedUnion(Set($0)) }
    }
}

/// SetAlgebra wrapper whose `intersection(_:)` returns the empty set
/// unconditionally — violates intersectionIdempotence whenever the input is
/// non-empty.
struct EmptyingIntersection: SetAlgebra, Equatable, Sendable, CustomStringConvertible {
    typealias Element = Int

    var underlying: Set<Int>

    init() { self.underlying = [] }
    init(_ elements: Set<Int>) { self.underlying = elements }

    func contains(_ member: Int) -> Bool { underlying.contains(member) }

    func union(_ other: EmptyingIntersection) -> EmptyingIntersection {
        EmptyingIntersection(underlying.union(other.underlying))
    }

    // The bug: intersection always returns the empty set.
    func intersection(_ other: EmptyingIntersection) -> EmptyingIntersection {
        EmptyingIntersection()
    }

    func symmetricDifference(_ other: EmptyingIntersection) -> EmptyingIntersection {
        EmptyingIntersection(underlying.symmetricDifference(other.underlying))
    }

    mutating func formUnion(_ other: EmptyingIntersection) {
        underlying.formUnion(other.underlying)
    }
    mutating func formIntersection(_ other: EmptyingIntersection) {
        underlying = []
    }
    mutating func formSymmetricDifference(_ other: EmptyingIntersection) {
        underlying.formSymmetricDifference(other.underlying)
    }

    @discardableResult
    mutating func insert(
        _ newMember: Int
    ) -> (inserted: Bool, memberAfterInsert: Int) {
        underlying.insert(newMember)
    }
    @discardableResult
    mutating func remove(_ member: Int) -> Int? { underlying.remove(member) }
    @discardableResult
    mutating func update(with newMember: Int) -> Int? {
        underlying.update(with: newMember)
    }

    static func == (lhs: EmptyingIntersection, rhs: EmptyingIntersection) -> Bool {
        lhs.underlying == rhs.underlying
    }

    var description: String {
        "EI(\(underlying.sorted()))"
    }
}

extension Gen where Value == EmptyingIntersection {
    static func emptyingIntersection() -> Generator<EmptyingIntersection, some SendableSequenceType> {
        Gen<Int>.int(in: 0...20)
            .array(of: 1...4) // at least one element so idempotence is non-trivial
            .map { EmptyingIntersection(Set($0)) }
    }
}
