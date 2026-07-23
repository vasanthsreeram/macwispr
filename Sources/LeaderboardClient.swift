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

/// Snapshot of the caller's public board identity.
struct LeaderboardStanding: Equatable, Sendable {
    var rank: Int?
    var displayName: String
    var shortName: String
    var animal: String
    var avatarKey: String
    var stats: LeaderboardStats
    var isSeed: Bool
    /// True when the user set a competitive public name (not Anonymous Animal).
    var isCustomName: Bool

    static let empty = LeaderboardStanding(
        rank: nil,
        displayName: "",
        shortName: "",
        animal: "",
        avatarKey: "",
        stats: .zero,
        isSeed: false,
        isCustomName: false
    )
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
    private static let rankKey = "leaderboardRank"
    private static let shortNameKey = "leaderboardShortName"
    private static let animalKey = "leaderboardAnimal"
    private static let avatarKeyKey = "leaderboardAvatarKey"
    private static let isCustomNameKey = "leaderboardIsCustomName"
    /// User-chosen competitive name (empty = stay anonymous animal). Local draft until sync.
    private static let publicNameKey = "leaderboardPublicName"
    private static let lastSyncKey = "leaderboardLastSyncAt"
    private static let lastNameErrorKey = "leaderboardLastNameError"
    private static let keychainService = "com.macwispr.leaderboard"
    private static let keychainAccount = "participant_token"

    /// Max length for a public competitive name (matches API).
    static let publicNameMaxLength = 24

    private let queue = DispatchQueue(label: "com.macwispr.leaderboard", qos: .utility)
    private var syncWorkItem: DispatchWorkItem?
    private let syncDebounceSeconds: TimeInterval = 12
    private let session: URLSession

    /// Fired on main after a successful sync / rank refresh.
    var onStandingChanged: ((LeaderboardStanding) -> Void)?

    private init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 30
        config.waitsForConnectivity = false
        config.httpCookieAcceptPolicy = .never
        config.httpShouldSetCookies = false
        session = URLSession(configuration: config)
    }

    // MARK: - Opt-in

    var isOptedIn: Bool {
        UserDefaults.standard.bool(forKey: Self.optInKey)
    }

    /// Cached standing from last successful network response (or empty).
    var standing: LeaderboardStanding {
        let defaults = UserDefaults.standard
        let rankRaw = defaults.object(forKey: Self.rankKey) as? Int
        return LeaderboardStanding(
            rank: rankRaw,
            displayName: defaults.string(forKey: Self.displayNameKey) ?? "",
            shortName: defaults.string(forKey: Self.shortNameKey) ?? "",
            animal: defaults.string(forKey: Self.animalKey) ?? "",
            avatarKey: defaults.string(forKey: Self.avatarKeyKey) ?? "",
            stats: .zero,
            isSeed: false,
            isCustomName: defaults.bool(forKey: Self.isCustomNameKey)
        )
    }

    var displayName: String { standing.displayName }
    var rank: Int? { standing.rank }

    /// Draft public name the user typed (empty = anonymous animal).
    var publicName: String {
        get { UserDefaults.standard.string(forKey: Self.publicNameKey) ?? "" }
        set {
            let trimmed = Self.sanitizeLocalPublicName(newValue)
            UserDefaults.standard.set(trimmed, forKey: Self.publicNameKey)
        }
    }

    /// Last name-related API error (`name_taken`, `invalid_name_chars`, …), if any.
    var lastNameError: String? {
        UserDefaults.standard.string(forKey: Self.lastNameErrorKey)
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
            clearStandingDefaults()
            try? deleteToken()
            if let token {
                queue.async { [weak self] in
                    self?.deleteRemote(token: token)
                }
            }
            DispatchQueue.main.async { [weak self] in
                self?.onStandingChanged?(.empty)
            }
        }
    }

    /// Update competitive public name (empty clears to anonymous) and force-sync.
    func setPublicName(_ name: String, statsProvider: @escaping () -> LeaderboardStats) {
        publicName = name
        UserDefaults.standard.removeObject(forKey: Self.lastNameErrorKey)
        guard isOptedIn else { return }
        scheduleSync(statsProvider: statsProvider, force: true)
    }

    /// Local pre-check before network (UI).
    static func sanitizeLocalPublicName(_ raw: String) -> String {
        let collapsed = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        if collapsed.count > publicNameMaxLength {
            return String(collapsed.prefix(publicNameMaxLength))
        }
        return collapsed
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

    /// Refresh rank without writing new stats (Home on appear).
    func refreshStanding(completion: ((LeaderboardStanding) -> Void)? = nil) {
        guard isOptedIn, let token = loadToken() else {
            completion?(.empty)
            return
        }
        queue.async { [weak self] in
            self?.fetchMe(token: token, completion: completion)
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
        request.setValue("MacWispr-Leaderboard/1", forHTTPHeaderField: "User-Agent")

        var body: [String: Any] = [
            "dictations": stats.dictations,
            "words": stats.words,
            "time_saved_minutes": stats.timeSavedMinutes,
            "streak_days": stats.streakDays,
        ]
        // Empty string → server keeps / assigns anonymous animal.
        body["public_name"] = publicName

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        session.dataTask(with: request) { [weak self] data, response, error in
            guard error == nil,
                  let http = response as? HTTPURLResponse,
                  let data
            else { return }

            if http.statusCode == 409 || http.statusCode == 400,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let err = json["error"] as? String
            {
                UserDefaults.standard.set(err, forKey: Self.lastNameErrorKey)
                DispatchQueue.main.async {
                    // Keep prior standing; surface name error via standing callback with cached rank.
                    if let standing = self?.standing {
                        self?.onStandingChanged?(standing)
                    }
                }
                return
            }

            guard (200...299).contains(http.statusCode),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return }

            UserDefaults.standard.removeObject(forKey: Self.lastNameErrorKey)
            let standing = self?.applyStandingJSON(json, fallbackStats: stats) ?? .empty
            UserDefaults.standard.set(Date(), forKey: Self.lastSyncKey)
            DispatchQueue.main.async {
                self?.onStandingChanged?(standing)
            }
        }.resume()
    }

    private func fetchMe(token: String, completion: ((LeaderboardStanding) -> Void)?) {
        var request = URLRequest(url: Self.apiBaseURL.appendingPathComponent("v1/me"))
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("MacWispr-Leaderboard/1", forHTTPHeaderField: "User-Agent")

        session.dataTask(with: request) { [weak self] data, response, error in
            guard error == nil,
                  let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode),
                  let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                DispatchQueue.main.async { completion?(self?.standing ?? .empty) }
                return
            }
            let standing = self?.applyStandingJSON(json, fallbackStats: .zero) ?? .empty
            DispatchQueue.main.async {
                self?.onStandingChanged?(standing)
                completion?(standing)
            }
        }.resume()
    }

    private func applyStandingJSON(_ json: [String: Any], fallbackStats: LeaderboardStats) -> LeaderboardStanding {
        let defaults = UserDefaults.standard
        if let name = json["display_name"] as? String, !name.isEmpty {
            defaults.set(name, forKey: Self.displayNameKey)
        }
        if let short = json["short_name"] as? String, !short.isEmpty {
            defaults.set(short, forKey: Self.shortNameKey)
        }
        if let animal = json["animal"] as? String, !animal.isEmpty {
            defaults.set(animal, forKey: Self.animalKey)
        }
        if let avatar = json["avatar_key"] as? String, !avatar.isEmpty {
            defaults.set(avatar, forKey: Self.avatarKeyKey)
        }
        let isCustom = (json["is_custom_name"] as? Bool)
            ?? ((json["is_custom_name"] as? Int).map { $0 != 0 })
            ?? false
        defaults.set(isCustom, forKey: Self.isCustomNameKey)
        // Keep local draft in sync when server accepted a custom name.
        if isCustom, let short = json["short_name"] as? String, !short.isEmpty {
            defaults.set(short, forKey: Self.publicNameKey)
        } else if !isCustom {
            // Server is anonymous — leave draft as-is so user can still type a name.
        }
        if let rank = json["rank"] as? Int {
            defaults.set(rank, forKey: Self.rankKey)
        } else if let rank = json["rank"] as? Double {
            defaults.set(Int(rank), forKey: Self.rankKey)
        }

        let stats = LeaderboardStats(
            dictations: (json["dictations"] as? Int)
                ?? (json["dictations"] as? Double).map { Int($0) }
                ?? fallbackStats.dictations,
            words: (json["words"] as? Int)
                ?? (json["words"] as? Double).map { Int($0) }
                ?? fallbackStats.words,
            timeSavedMinutes: (json["time_saved_minutes"] as? Double)
                ?? (json["time_saved_minutes"] as? Int).map { Double($0) }
                ?? fallbackStats.timeSavedMinutes,
            streakDays: (json["streak_days"] as? Int)
                ?? (json["streak_days"] as? Double).map { Int($0) }
                ?? fallbackStats.streakDays
        )

        return LeaderboardStanding(
            rank: defaults.object(forKey: Self.rankKey) as? Int,
            displayName: defaults.string(forKey: Self.displayNameKey) ?? "",
            shortName: defaults.string(forKey: Self.shortNameKey) ?? "",
            animal: defaults.string(forKey: Self.animalKey) ?? "",
            avatarKey: defaults.string(forKey: Self.avatarKeyKey) ?? "",
            stats: stats,
            isSeed: (json["is_seed"] as? Bool) ?? false,
            isCustomName: isCustom
        )
    }

    private func clearStandingDefaults() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: Self.displayNameKey)
        defaults.removeObject(forKey: Self.rankKey)
        defaults.removeObject(forKey: Self.shortNameKey)
        defaults.removeObject(forKey: Self.animalKey)
        defaults.removeObject(forKey: Self.avatarKeyKey)
        defaults.removeObject(forKey: Self.isCustomNameKey)
        defaults.removeObject(forKey: Self.publicNameKey)
        defaults.removeObject(forKey: Self.lastNameErrorKey)
        defaults.removeObject(forKey: Self.lastSyncKey)
    }

    private func deleteRemote(token: String) {
        var request = URLRequest(url: Self.apiBaseURL.appendingPathComponent("v1/me"))
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("MacWispr-Leaderboard/1", forHTTPHeaderField: "User-Agent")
        session.dataTask(with: request) { _, _, _ in }.resume()
    }

    // MARK: - Token (Keychain)

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
