import Foundation

/// Opt-in / opt-out state for the public leaderboard.
///
/// Opt-out must not forget the participant token until the server confirms the
/// row is gone, otherwise an offline or 5xx opt-out leaves the public row
/// orphaned forever. States: opted-in -> pending-deletion -> cleared.
public struct LeaderboardParticipation: Equatable, Sendable {
    public enum DeletionOutcome: Equatable, Sendable {
        case status(Int)
        case transportError
    }

    public var optedIn: Bool
    /// Active token (nil when opted out).
    public var token: String?
    /// Tokens whose server-side DELETE has not been confirmed yet (oldest first).
    public var pendingDeletionTokens: [String]

    public init(optedIn: Bool = false, token: String? = nil, pendingDeletionTokens: [String] = []) {
        self.optedIn = optedIn
        self.token = token
        self.pendingDeletionTokens = pendingDeletionTokens
    }

    /// Next token to DELETE, if any.
    public var nextDeletionToken: String? { pendingDeletionTokens.first }

    /// 2xx = deleted, 404 = already gone. Anything else must be retried.
    public static func isDeletionConfirmed(_ outcome: DeletionOutcome) -> Bool {
        switch outcome {
        case .status(let code): return (200...299).contains(code) || code == 404
        case .transportError: return false
        }
    }

    public mutating func optIn(newToken: String) {
        optedIn = true
        token = newToken
    }

    /// Move the live token into pending-deletion; never drops it silently.
    public mutating func optOut() {
        optedIn = false
        if let token, !pendingDeletionTokens.contains(token) { pendingDeletionTokens.append(token) }
        token = nil
    }

    public mutating func deletionFinished(_ outcome: DeletionOutcome, token deleted: String? = nil) {
        guard Self.isDeletionConfirmed(outcome), let deleted = deleted ?? nextDeletionToken else { return }
        pendingDeletionTokens.removeAll { $0 == deleted }
    }

    /// A PUT/GET completion may only touch local state if still opted in with the same token.
    public func shouldApplySyncResult(forToken requestToken: String) -> Bool {
        optedIn && token == requestToken
    }
}
