import Foundation

/// Persisted queue of leaderboard tokens whose server row must still be DELETEd.
/// A token leaves the queue only after the server confirms (2xx/404), so an
/// offline or 5xx opt-out is retried (launch, connectivity return).
/// Thread-safe; `send` performs one DELETE and reports its outcome.
public final class LeaderboardDeletionCoordinator: @unchecked Sendable {
    public typealias Send = @Sendable (_ token: String, _ completion: @escaping @Sendable (LeaderboardParticipation.DeletionOutcome) -> Void) -> Void

    private let load: () -> [String]
    private let save: ([String]) -> Void
    private let send: Send
    private let lock = NSLock()
    private var inFlight = false

    public init(load: @escaping () -> [String], save: @escaping ([String]) -> Void, send: @escaping Send) {
        self.load = load
        self.save = save
        self.send = send
    }

    public var pendingTokens: [String] {
        lock.lock(); defer { lock.unlock() }
        return load()
    }

    /// Persist `token` as pending deletion (no-op when nil), then try to delete it.
    public func optOut(token: String?) {
        if let token {
            lock.lock()
            var state = LeaderboardParticipation(optedIn: true, token: token, pendingDeletionTokens: load())
            state.optOut()
            save(state.pendingDeletionTokens)
            lock.unlock()
        }
        attempt()
    }

    /// DELETE the oldest pending token; continue with the next after each success.
    public func attempt() {
        lock.lock()
        guard !inFlight, let token = LeaderboardParticipation(pendingDeletionTokens: load()).nextDeletionToken else {
            lock.unlock()
            return
        }
        inFlight = true
        lock.unlock()
        send(token) { [weak self] outcome in
            guard let self else { return }
            self.lock.lock()
            self.inFlight = false
            // Re-read: opt-out may have appended tokens while the DELETE was in flight.
            var state = LeaderboardParticipation(pendingDeletionTokens: self.load())
            state.deletionFinished(outcome, token: token)
            self.save(state.pendingDeletionTokens)
            self.lock.unlock()
            if LeaderboardParticipation.isDeletionConfirmed(outcome) { self.attempt() }
        }
    }
}
