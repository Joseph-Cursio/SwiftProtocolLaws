/// A user-supplied filter that suppresses individual actions in a
/// randomly-generated action sequence when they violate a stateful
/// pre-condition. The kit ships the protocol shape only — specific
/// curated guards (e.g. `.noDoubleDelete`, `.requireLogin`,
/// `.maxConcurrentTasks(N)`) are not committed to the v2.2.0 surface;
/// they're examples in the SwiftInferProperties v2.0 PRD §8.1 and
/// the calibration corpus may suggest which guards belong in a future
/// minor.
///
/// **Why per-element filtering, not per-sequence rejection.**
/// `wouldAllow(_:given:)` is consulted **once per candidate action**,
/// not once per sequence. When a guard refuses, the candidate is
/// dropped and generation moves on to the next candidate — the
/// resulting sequence may be shorter than the requested length, but
/// it always satisfies every guard by construction. Per-sequence
/// rejection (re-roll the whole sequence on any rejection) would
/// loop forever under restrictive guards; this shape terminates by
/// construction and matches the v2.0 PRD §16 #4 hard guarantee.
///
/// **Why an `[Action]` history, not state.** Guards see the history
/// of *previously-accepted* actions, not the reducer's State. The
/// reducer is the consumer's, not the kit's — and guards need to
/// fire pre-reducer-call to be useful (post-reducer-call guards
/// would already have applied the action). The history is the only
/// stateful signal the kit can plumb without taking a runtime
/// dependency on the consumer's reducer.
///
/// **Sendable.** Both the protocol and its `Action` are `Sendable` so
/// the guard can be captured by the action-sequence generator's
/// `@Sendable` closure (matches `Generator`'s `@Sendable` capture
/// requirements).
public protocol StatefulGuard<Action>: Sendable {
    associatedtype Action: Sendable

    /// Should `next` be accepted into the sequence, given the prior
    /// `history` of already-accepted actions? Returning `false`
    /// drops `next` from the sequence; the next candidate from the
    /// underlying action generator is tried in its place.
    func wouldAllow(_ next: Action, given history: [Action]) -> Bool
}
