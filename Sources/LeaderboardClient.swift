import Foundation
import Security

// MARK: - Public opt-in leaderboard (anonymous)
//
// Separate from product telemetry (PostHog). When enabled:
// - App holds a random secret token in Keychain (never the install UUID).
// - Server stores only SHA-256(token) + aggregates + a server-derived
//   "Anonymous <Animal> · <tag>" display name.
// - Maintainers cannot reverse a board row to a person or device.
// - Never sends: transcript text, audio, email, GitHub, real name, install ID.

/// Aggregate stats posted to the public board (counts only — no content).
struct LeaderboardStats: Equatable, Sendable {
    var dictations: Int
    var words: Int
    var timeSavedMinutes: Double
    var streakDays: Int

    static let zero = LeaderboardStats(dictations: 0, words: 0, timeSavedMinutes: 0, streakDays: 0)
}

/// Privacy-first client for the public leaderboard API.
final class LeaderboardClient: @unchecked Sendable {
    static let shared = LeaderboardClient()

    /// Production Worker (Cloudflare). HTTPS only.
    static let apiBaseURL = URL(string: "https://macwispr-leaderboard.s-vasanthrojin.workers.dev")!

    /// Public website board (edgy marketing site).
    static let publicBoardURL = URL(string: "https://fuckwisprflow.com/leaderboard")!

    private static let optInKey = "leaderboardOptIn"
    private static let displayNameKey = "leaderboardDisplayName"
    private static let lastSyncKey = "leaderboardLastSyncAt"
    private static let keychainService = "com.macwispr.leaderboard"
    private static let keychainAccount = "participant_token"

    private let queue = DispatchQueue(label: "com.macwispr.leaderboard", qos: .utility)
    private var syncWorkItem: DispatchWorkItem?
    private let syncDebounceSeconds: TimeInterval = 12
    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 30
        config.waitsForConnectivity = false
        // Do not send cookies; minimize ambient identifiers.
        config.httpCookieAcceptPolicy = .never
        config.httpShouldSetCookies = false
        session = URLSession(configuration: config)
    }

    // MARK: - Opt-in

    var isOptedIn: Bool {
        UserDefaults.standard.bool(forKey: Self.optInKey)
    }

    /// Server-derived anonymous label (e.g. "Anonymous Otter · a1f2"). Empty until first sync.
    var displayName: String {
        UserDefaults.standard.string(forKey: Self.displayNameKey) ?? ""
    }

    /// Enable or disable public board participation.
    /// Opt-out deletes the server row (if reachable) and destroys the local token.
    func setOptIn(_ enabled: Bool, statsProvider: @escaping () -> LeaderboardStats) {
        if enabled {
            UserDefaults.standard.set(true, forKey: Self.optInKey)
            _ = ensureToken()
            scheduleSync(statsProvider: statsProvider, force: true)
        } else {
            let token = loadToken()
            UserDefaults.standard.set(false, forKey: Self.optInKey)
            UserDefaults.standard.removeObject(forKey: Self.displayNameKey)
            UserDefaults.standard.removeObject(forKey: Self.lastSyncKey)
            // Drop local identity so re-opt-in starts a fresh anonymous row.
            try? deleteToken()
            if let token {
                queue.async { [weak self] in
                    self?.deleteRemote(token: token)
                }
            }
        }
    }

    /// Debounced upsert after dictation / settings changes.
    func scheduleSync(statsProvider: @escaping () -> LeaderboardStats, force: Bool = false) {
        guard isOptedIn else { return }
        queue.async { [weak self] in
            guard let self else { return }
            self.syncWorkItem?.cancel()
            let work = DispatchWorkItem { [weak self] in
                self?.performSync(stats: statsProvider(), force: force)
            }
            self.syncWorkItem = work
            let delay = force ? 0.05 : self.syncDebounceSeconds
            self.queue.asyncAfter(deadline: .now() + delay, execute: work)
        }
    }

    // MARK: - Sync

    private func performSync(stats: LeaderboardStats, force: Bool) {
        guard isOptedIn else { return }
        guard let token = ensureToken() else { return }

        if !force,
           let last = UserDefaults.standard.object(forKey: Self.lastSyncKey) as? Date,
           Date().timeIntervalSince(last) < 30
        {
            return
        }

        var request = URLRequest(url: Self.apiBaseURL.appendingPathComponent("v1/me"))
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        // Avoid defaulting to identifiable User-Agent patterns where possible.
        request.setValue("MacWispr-Leaderboard/1", forHTTPHeaderField: "User-Agent")

        let body: [String: Any] = [
            "dictations": stats.dictations,
            "words": stats.words,
            "time_saved_minutes": stats.timeSavedMinutes,
            "streak_days": stats.streakDays,
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        session.dataTask(with: request) { [weak self] data, response, error in
            // Fail-silent: board sync must never affect dictation.
            guard error == nil,
                  let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode),
                  let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return }

            if let name = json["display_name"] as? String, !name.isEmpty {
                UserDefaults.standard.set(name, forKey: Self.displayNameKey)
            }
            UserDefaults.standard.set(Date(), forKey: Self.lastSyncKey)
            _ = self
        }.resume()
    }

    private func deleteRemote(token: String) {
        var request = URLRequest(url: Self.apiBaseURL.appendingPathComponent("v1/me"))
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("MacWispr-Leaderboard/1", forHTTPHeaderField: "User-Agent")
        session.dataTask(with: request) { _, _, _ in
            // Best-effort leave; local identity already wiped.
        }.resume()
    }

    // MARK: - Token (Keychain)

    /// Random 32-byte secret, base64url, never derived from install ID or hardware.
    @discardableResult
    private func ensureToken() -> String? {
        if let existing = loadToken(), existing.count >= 32 {
            return existing
        }
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else { return nil }
        let token = Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        do {
            try saveToken(token)
            return token
        } catch {
            return nil
        }
    }

    private func loadToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: Self.keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let string = String(data: data, encoding: .utf8),
              !string.isEmpty
        else { return nil }
        return string
    }

    private func saveToken(_ value: String) throws {
        guard let data = value.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: Self.keychainAccount,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        if status == errSecSuccess {
            let update = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            guard update == errSecSuccess else { throw LeaderboardKeychainError.unhandled(update) }
        } else if status == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let addStatus = SecItemAdd(add as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw LeaderboardKeychainError.unhandled(addStatus) }
        } else {
            throw LeaderboardKeychainError.unhandled(status)
        }
    }

    private func deleteToken() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: Self.keychainAccount,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw LeaderboardKeychainError.unhandled(status)
        }
    }
}

private enum LeaderboardKeychainError: Error {
    case unhandled(OSStatus)
}

// MARK: - Stats helpers

extension UsageStats {
    /// Consecutive calendar days (including today or yesterday) with ≥1 dictation.
    static func currentStreakDays(entries: [TranscriptionEntry], reference: Date = Date(), calendar: Calendar = .current) -> Int {
        guard !entries.isEmpty else { return 0 }
        let daysWithActivity = Set(entries.map { calendar.startOfDay(for: $0.timestamp) })
        var cursor = calendar.startOfDay(for: reference)
        // Allow streak to start from yesterday if nothing today yet.
        if !daysWithActivity.contains(cursor) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor) else { return 0 }
            cursor = yesterday
            if !daysWithActivity.contains(cursor) { return 0 }
        }
        var streak = 0
        while daysWithActivity.contains(cursor) {
            streak += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }
        return streak
    }

    /// All-time board payload from on-device history.
    func leaderboardStats(entries: [TranscriptionEntry], reference: Date = Date()) -> LeaderboardStats {
        let snap = allTimeSnapshot(entries: entries)
        return LeaderboardStats(
            dictations: snap.dictations,
            words: snap.words,
            timeSavedMinutes: snap.timeSavedMinutes,
            streakDays: Self.currentStreakDays(entries: entries, reference: reference)
        )
    }
}
