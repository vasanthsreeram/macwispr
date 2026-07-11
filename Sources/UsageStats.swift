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
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        let startOfToday = calendar.startOfDay(for: reference)
        var buckets: [DayBucket] = []

        for offset in (0..<7).reversed() {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: startOfToday) else { continue }
            let next = calendar.date(byAdding: .day, value: 1, to: day) ?? day
            let interval = DateInterval(start: day, end: next)
            let snap = snapshot(for: entries, in: interval)
            buckets.append(
                DayBucket(
                    id: ISO8601DateFormatter().string(from: day),
                    date: day,
                    label: formatter.string(from: day),
                    words: snap.words,
                    timeSavedMinutes: snap.timeSavedMinutes
                )
            )
        }
        return buckets
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

    /// Keep only the newest `maxEntries` in the mutable array (in place).
    static func trimInPlace(_ entries: inout [TranscriptionEntry]) {
        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }
    }
}
