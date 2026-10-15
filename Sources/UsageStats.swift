import Foundation

/// Aggregates dictation history into word counts and estimated time saved.
/// Typing baseline defaults to 40 WPM (common knowledge-worker average).
struct UsageStats {
    static let defaultTypingWPM: Double = 40

    struct Snapshot: Equatable {
        var words: Int
        var dictations: Int
        var audioSeconds: Double
        var typingMinutes: Double
        var timeSavedMinutes: Double

        static let zero = Snapshot(words: 0, dictations: 0, audioSeconds: 0, typingMinutes: 0, timeSavedMinutes: 0)

        var formattedTimeSaved: String {
            Self.formatDuration(minutes: timeSavedMinutes)
        }

        var formattedAudio: String {
            Self.formatDuration(minutes: audioSeconds / 60.0)
        }

        static func formatDuration(minutes: Double) -> String {
            let totalSeconds = max(0, Int((minutes * 60).rounded()))
            let h = totalSeconds / 3600
            let m = (totalSeconds % 3600) / 60
            let s = totalSeconds % 60
            if h > 0 { return String(format: "%dh %dm", h, m) }
            if m > 0 { return String(format: "%dm %ds", m, s) }
            return String(format: "%ds", s)
        }
    }

    struct DayBucket: Identifiable, Equatable {
        let id: String
        let date: Date
        let label: String
        let words: Int
        let timeSavedMinutes: Double
    }

    let typingWPM: Double

    init(typingWPM: Double = UsageStats.defaultTypingWPM) {
        self.typingWPM = max(1, typingWPM)
    }

    static func wordCount(in text: String) -> Int {
        text.split { $0.isWhitespace || $0.isNewline }.filter { !$0.isEmpty }.count
    }

    func snapshot(for entries: [TranscriptionEntry], in interval: DateInterval? = nil) -> Snapshot {
        let filtered: [TranscriptionEntry]
        if let interval {
            filtered = entries.filter { interval.contains($0.timestamp) }
        } else {
            filtered = entries
        }

        var words = 0
        var audioSeconds = 0.0
        for entry in filtered {
            words += entry.wordCount > 0 ? entry.wordCount : Self.wordCount(in: entry.text)
            audioSeconds += entry.duration
        }

        let typingMinutes = Double(words) / typingWPM
        let audioMinutes = audioSeconds / 60.0
        let saved = max(0, typingMinutes - audioMinutes)

        return Snapshot(
            words: words,
            dictations: filtered.count,
            audioSeconds: audioSeconds,
            typingMinutes: typingMinutes,
            timeSavedMinutes: saved
        )
    }

    func weekInterval(reference: Date = Date(), calendar: Calendar = .current) -> DateInterval {
        let startOfToday = calendar.startOfDay(for: reference)
        let start = calendar.date(byAdding: .day, value: -6, to: startOfToday) ?? startOfToday
        let end = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? reference
        return DateInterval(start: start, end: end)
    }

    func weeklySnapshot(entries: [TranscriptionEntry], reference: Date = Date()) -> Snapshot {
        snapshot(for: entries, in: weekInterval(reference: reference))
    }

    func allTimeSnapshot(entries: [TranscriptionEntry]) -> Snapshot {
        snapshot(for: entries)
    }

    func lastSevenDays(entries: [TranscriptionEntry], reference: Date = Date(), calendar: Calendar = .current) -> [DayBucket] {
        summary(entries: entries, reference: reference, calendar: calendar).days
    }

    /// Everything the dashboard and menu bar show, from one pass over history.
    struct Summary: Equatable {
        var week: Snapshot
        var allTime: Snapshot
        var days: [DayBucket]
        var streakDays: Int

        static let empty = Summary(week: .zero, allTime: .zero, days: [], streakDays: 0)
    }

    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f
    }()

    func summary(entries: [TranscriptionEntry], reference: Date = Date(), calendar: Calendar = .current) -> Summary {
        let startOfToday = calendar.startOfDay(for: reference)
        let dayStarts: [Date] = (0..<7).reversed().compactMap {
            calendar.date(byAdding: .day, value: -$0, to: startOfToday)
        }
        let weekStart = dayStarts.first ?? startOfToday
        let weekEnd = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? reference

        var dayWords = [Int](repeating: 0, count: dayStarts.count)
        var dayAudio = [Double](repeating: 0, count: dayStarts.count)
        var weekWords = 0, weekCount = 0, weekAudio = 0.0
        var allWords = 0, allAudio = 0.0
        var activeDays = Set<Date>()

        for entry in entries {
            let words = entry.wordCount > 0 ? entry.wordCount : Self.wordCount(in: entry.text)
            allWords += words
            allAudio += entry.duration
            activeDays.insert(calendar.startOfDay(for: entry.timestamp))
            guard entry.timestamp >= weekStart, entry.timestamp < weekEnd else { continue }
            weekWords += words
            weekCount += 1
            weekAudio += entry.duration
            if let i = dayStarts.lastIndex(where: { $0 <= entry.timestamp }) {
                dayWords[i] += words
                dayAudio[i] += entry.duration
            }
        }

        let days = dayStarts.enumerated().map { i, day in
            DayBucket(
                id: "\(Int(day.timeIntervalSince1970))",
                date: day,
                label: Self.weekdayFormatter.string(from: day),
                words: dayWords[i],
                timeSavedMinutes: makeSnapshot(words: dayWords[i], count: 0, audioSeconds: dayAudio[i]).timeSavedMinutes
            )
        }

        var streak = 0
        var cursor = startOfToday
        if !activeDays.contains(cursor) {
            cursor = calendar.date(byAdding: .day, value: -1, to: cursor) ?? cursor
        }
        while activeDays.contains(cursor) {
            streak += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }

        return Summary(
            week: makeSnapshot(words: weekWords, count: weekCount, audioSeconds: weekAudio),
            allTime: makeSnapshot(words: allWords, count: entries.count, audioSeconds: allAudio),
            days: days,
            streakDays: streak
        )
    }

    private func makeSnapshot(words: Int, count: Int, audioSeconds: Double) -> Snapshot {
        let typingMinutes = Double(words) / typingWPM
        return Snapshot(
            words: words,
            dictations: count,
            audioSeconds: audioSeconds,
            typingMinutes: typingMinutes,
            timeSavedMinutes: max(0, typingMinutes - audioSeconds / 60.0)
        )
    }
}

enum HistoryStore {
    /// Hard cap for in-memory and on-disk history (newest first).
    static let maxEntries = 2000

    private static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("MacWispr", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.json")
    }

    static func load() -> [TranscriptionEntry] {
        let url = fileURL
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let entries = (try? decoder.decode([TranscriptionEntry].self, from: data)) ?? []
        return Array(entries.prefix(maxEntries))
    }

    static func save(_ entries: [TranscriptionEntry]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        // Compact JSON — less disk churn than pretty-printed full rewrites.
        encoder.outputFormatting = [.sortedKeys]
        let trimmed = Array(entries.prefix(maxEntries))
        guard let data = try? encoder.encode(trimmed) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    /// Serial so a later snapshot can never be overwritten by an earlier one.
    private static let saveQueue = DispatchQueue(label: "macwispr.history.save", qos: .utility)

    /// JSON-encodes and writes 2,000 entries off the main thread.
    static func saveInBackground(_ entries: [TranscriptionEntry]) {
        saveQueue.async { save(entries) }
    }

    /// Blocks until queued writes finish (app termination).
    static func flushPendingSaves() {
        saveQueue.sync {}
    }

    /// Keep only the newest `maxEntries` in the mutable array (in place).
    static func trimInPlace(_ entries: inout [TranscriptionEntry]) {
        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }
    }
}
