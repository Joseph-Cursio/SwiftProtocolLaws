import Foundation

/// A small value-type struct used as the third stdlib-adjacent target for
/// green-path tests. Hand-written `Equatable`/`Hashable` so the law checker
/// is exercising real implementations rather than synthesized ones.
struct Coordinate: Equatable, Hashable, Sendable, CustomStringConvertible {
    let x: Int
    let y: Int

    static func == (lhs: Coordinate, rhs: Coordinate) -> Bool {
        lhs.x == rhs.x && lhs.y == rhs.y
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(x)
        hasher.combine(y)
    }

    var description: String { "(\(x), \(y))" }
}
