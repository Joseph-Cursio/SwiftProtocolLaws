import Foundation
import PropertyBased

/// Opaque, replayable seed for a property law check.
///
/// Wraps the four-`UInt64` state used by ``Xoshiro``. The `description` is the
/// base64 form returned by `Xoshiro.currentSeed` on Foundation platforms, which
/// makes seeds copy-pasteable from CI logs into ``Seed/init(base64:)`` for replay.
public struct Seed: Sendable, Hashable, CustomStringConvertible {
    public let rawValue: (UInt64, UInt64, UInt64, UInt64)

    public init(rawValue: (UInt64, UInt64, UInt64, UInt64)) {
        self.rawValue = rawValue
    }

    public init?(base64: String) {
        var rng = Xoshiro(seed: (0, 0, 0, 0))
        guard let restored = Xoshiro(seed: base64) else { return nil }
        rng = restored
        self.rawValue = rng.currentState
    }

    public var description: String {
        let rng = Xoshiro(seed: rawValue)
        return rng.currentSeed
    }

    public static func == (lhs: Seed, rhs: Seed) -> Bool {
        lhs.rawValue == rhs.rawValue
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(rawValue.0)
        hasher.combine(rawValue.1)
        hasher.combine(rawValue.2)
        hasher.combine(rawValue.3)
    }
}
