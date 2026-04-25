import Foundation
import PropertyBased

/// Violates Hashable.equalityConsistency: `==` always returns true (so any two
/// instances are equal) but `hash(into:)` derives from a stored UUID — every
/// instance hashes differently. This guarantees the equality-consistency law
/// is hit on the very first trial that pulls two distinct values.
struct EqualButDifferentHash: Hashable, Sendable, CustomStringConvertible {
    let id: UUID

    init() { self.id = UUID() }

    static func == (lhs: EqualButDifferentHash, rhs: EqualButDifferentHash) -> Bool {
        true
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    var description: String { "EBH(\(id.uuidString.prefix(4)))" }
}

extension Gen where Value == EqualButDifferentHash {
    static func equalButDifferentHash() -> Generator<EqualButDifferentHash, some SendableSequenceType> {
        Gen<Int>.int(in: 0...1_000_000).map { _ in EqualButDifferentHash() }
    }
}

/// Violates Hashable.stabilityWithinProcess (Conventional tier) ONLY.
///
/// `==` deliberately returns `false` so the `equalityConsistency` law (Strict)
/// is vacuously satisfied — no two values are ever equal, so the implication
/// "x == y → x.hashValue == y.hashValue" is never tested. That isolates the
/// stability violation, which is what we want to verify the .strict
/// enforcement-mode escalation against.
struct UnstableHasher: Hashable, Sendable, CustomStringConvertible {
    let value: Int

    static func == (lhs: UnstableHasher, rhs: UnstableHasher) -> Bool {
        false
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(value)
        hasher.combine(UUID()) // fresh per call → unstable across reads
    }

    var description: String { "U(\(value))" }
}

extension Gen where Value == UnstableHasher {
    static func unstableHasher() -> Generator<UnstableHasher, some SendableSequenceType> {
        Gen<Int>.int(in: 0...100).map { UnstableHasher(value: $0) }
    }
}
