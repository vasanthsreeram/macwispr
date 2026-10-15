import Foundation

/// On-disk layout shared by the app, the `macwispr` CLI, and the MCP server.
/// Everything lives under `~/Library/Application Support/MacWispr` so agents
/// can read it without TCC prompts. `MACWISPR_DATA_DIR` overrides the root.
public struct MacWisprPaths: Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    public static var `default`: MacWisprPaths {
        if let override = ProcessInfo.processInfo.environment["MACWISPR_DATA_DIR"],
           !override.isEmpty
        {
            return MacWisprPaths(root: URL(fileURLWithPath: (override as NSString).expandingTildeInPath, isDirectory: true))
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return MacWisprPaths(root: base.appendingPathComponent("MacWispr", isDirectory: true))
    }

    public var historyFile: URL { root.appendingPathComponent("history.json") }
    public var meetingsDir: URL { root.appendingPathComponent("Meetings", isDirectory: true) }
    public var agentsReadme: URL { root.appendingPathComponent("AGENTS.md") }

    public func meetingDir(id: String) -> URL {
        meetingsDir.appendingPathComponent(id, isDirectory: true)
    }
}

/// One dictation, as stored in `history.json` (same fields as the app's `TranscriptionEntry`).
public struct DictationRecord: Codable, Equatable, Sendable {
    public let id: UUID
    public let text: String
    public let timestamp: Date
    public let duration: Double
    public let wordCount: Int

    public init(id: UUID = UUID(), text: String, timestamp: Date, duration: Double, wordCount: Int) {
        self.id = id
        self.text = text
        self.timestamp = timestamp
        self.duration = duration
        self.wordCount = wordCount
    }
}

public enum MeetingStatus: String, Codable, Sendable {
    case recording
    case processing
    case done
    case failed
    /// The app quit or crashed while recording or processing. Audio may still be on disk.
    case interrupted
}

public enum MeetingSource: String, Codable, Sendable {
    case microphone
    case system
}

/// `meeting.json` inside each meeting folder.
public struct MeetingMetadata: Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var startedAt: Date
    public var endedAt: Date?
    public var durationSeconds: Double
    public var status: MeetingStatus
    public var recordMicrophone: Bool
    public var recordSystemAudio: Bool
    public var model: String?
    public var wordCount: Int
    public var segmentCount: Int
    public var error: String?
    /// Non-fatal problems, e.g. system audio was silent because permission is off.
    public var warnings: [String]?

    public init(
        id: String,
        title: String,
        startedAt: Date,
        endedAt: Date? = nil,
        durationSeconds: Double = 0,
        status: MeetingStatus = .recording,
        recordMicrophone: Bool,
        recordSystemAudio: Bool,
        model: String? = nil,
        wordCount: Int = 0,
        segmentCount: Int = 0,
        error: String? = nil
    ) {
        self.id = id
        self.title = title
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.durationSeconds = durationSeconds
        self.status = status
        self.recordMicrophone = recordMicrophone
        self.recordSystemAudio = recordSystemAudio
        self.model = model
        self.wordCount = wordCount
        self.segmentCount = segmentCount
        self.error = error
    }

    /// Folder name for a meeting that starts at `date`: sortable and readable.
    public static func makeID(for date: Date, timeZone: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = "yyyy-MM-dd_HHmmss"
        return f.string(from: date)
    }

    public static func defaultTitle(for date: Date, timeZone: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return "Meeting \(f.string(from: date))"
    }
}

public struct MeetingSegment: Codable, Equatable, Sendable {
    /// Seconds from the start of the recording.
    public var start: Double
    public var end: Double
    public var source: MeetingSource
    public var text: String

    public init(start: Double, end: Double, source: MeetingSource, text: String) {
        self.start = start
        self.end = end
        self.source = source
        self.text = text
    }
}

/// `transcript.json` inside each meeting folder.
public struct MeetingTranscript: Codable, Equatable, Sendable {
    public var segments: [MeetingSegment]

    public init(segments: [MeetingSegment]) {
        self.segments = segments
    }

    public var plainText: String {
        segments.map(\.text).joined(separator: " ")
    }
}

/// File names inside a meeting folder.
public enum MeetingFiles {
    public static let metadata = "meeting.json"
    public static let transcriptJSON = "transcript.json"
    public static let transcriptMarkdown = "transcript.md"
    /// Microphone and system audio mixed together.
    public static let mixedAudio = "audio.m4a"
    public static let micAudio = "mic.m4a"
    public static let systemAudio = "system.m4a"
    /// Raw 16 kHz mono PCM16 written while recording; removed after processing.
    public static let micPCM = "mic.pcm"
    public static let systemPCM = "system.pcm"

    public static func pcm(_ source: MeetingSource) -> String {
        source == .microphone ? micPCM : systemPCM
    }

    public static func audio(_ source: MeetingSource) -> String {
        source == .microphone ? micAudio : systemAudio
    }
}

public enum MeetingTranscriptFormatter {
    /// "Me" / "Others" only when both sides were recorded; one source needs no label.
    public static func speakerLabel(_ source: MeetingSource, bothSources: Bool) -> String? {
        guard bothSources else { return nil }
        return source == .microphone ? "Me" : "Others"
    }

    public static func timestamp(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        return String(format: "%02d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }

    public static func markdown(meta: MeetingMetadata, transcript: MeetingTranscript) -> String {
        let both = meta.recordMicrophone && meta.recordSystemAudio
        let iso = ISO8601DateFormatter()
        var lines: [String] = [
            "# \(meta.title)",
            "",
            "- Started: \(iso.string(from: meta.startedAt))",
            "- Duration: \(UsageClock.format(seconds: meta.durationSeconds))",
            "- Sources: \(sourceList(meta))",
        ]
        if both {
            lines.append("- Speakers: Me = microphone, Others = system audio (other apps)")
        }
        lines.append("")
        if transcript.segments.isEmpty {
            lines.append("_No speech detected._")
        }
        for seg in transcript.segments {
            let stamp = "[\(timestamp(seg.start))]"
            if let label = speakerLabel(seg.source, bothSources: both) {
                lines.append("\(stamp) **\(label):** \(seg.text)")
            } else {
                lines.append("\(stamp) \(seg.text)")
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    static func sourceList(_ meta: MeetingMetadata) -> String {
        var parts: [String] = []
        if meta.recordMicrophone { parts.append("microphone") }
        if meta.recordSystemAudio { parts.append("system audio") }
        return parts.isEmpty ? "none" : parts.joined(separator: " + ")
    }
}

public enum UsageClock {
    public static func format(seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }
}

/// Read-only access to dictation history and meetings, for the CLI and MCP server.
public struct AgentDataStore: Sendable {
    public let paths: MacWisprPaths

    public init(paths: MacWisprPaths = .default) {
        self.paths = paths
    }

    static func makeDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    public static func makeEncoder(pretty: Bool = true) -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes] : [.sortedKeys, .withoutEscapingSlashes]
        return e
    }

    // MARK: History

    /// Newest first.
    public func dictations(since: Date? = nil, query: String? = nil, limit: Int? = nil) -> [DictationRecord] {
        guard let data = try? Data(contentsOf: paths.historyFile),
              let all = try? Self.makeDecoder().decode([DictationRecord].self, from: data)
        else { return [] }
        let q = query?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var out = all.filter { entry in
            if let since, entry.timestamp < since { return false }
            if !q.isEmpty, !entry.text.localizedCaseInsensitiveContains(q) { return false }
            return !entry.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        out.sort { $0.timestamp > $1.timestamp }
        if let limit, limit >= 0 { out = Array(out.prefix(limit)) }
        return out
    }

    // MARK: Meetings

    /// Newest first.
    public func meetings(limit: Int? = nil) -> [MeetingMetadata] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: paths.meetingsDir.path) else { return [] }
        var out: [MeetingMetadata] = []
        for name in names where !name.hasPrefix(".") {
            if let meta = meeting(id: name) { out.append(meta) }
        }
        out.sort { $0.startedAt > $1.startedAt }
        if let limit, limit >= 0 { out = Array(out.prefix(limit)) }
        return out
    }

    /// Accepts a folder id or `latest`.
    public func resolveMeetingID(_ idOrLatest: String) -> String? {
        let trimmed = idOrLatest.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.lowercased() == "latest" {
            return meetings(limit: 1).first?.id
        }
        // Reject path tricks; ids are plain folder names.
        guard !trimmed.contains("/"), !trimmed.contains("..") else { return nil }
        return meeting(id: trimmed) == nil ? nil : trimmed
    }

    public func meeting(id: String) -> MeetingMetadata? {
        let url = paths.meetingDir(id: id).appendingPathComponent(MeetingFiles.metadata)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? Self.makeDecoder().decode(MeetingMetadata.self, from: data)
    }

    public func transcript(id: String) -> MeetingTranscript? {
        let url = paths.meetingDir(id: id).appendingPathComponent(MeetingFiles.transcriptJSON)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? Self.makeDecoder().decode(MeetingTranscript.self, from: data)
    }

    public func transcriptMarkdown(id: String) -> String? {
        if let s = try? String(contentsOf: paths.meetingDir(id: id).appendingPathComponent(MeetingFiles.transcriptMarkdown), encoding: .utf8) {
            return s
        }
        guard let meta = meeting(id: id), let t = transcript(id: id) else { return nil }
        return MeetingTranscriptFormatter.markdown(meta: meta, transcript: t)
    }

    /// Existing audio and transcript files for a meeting, keyed by role.
    public func meetingFiles(id: String) -> [String: String] {
        let dir = paths.meetingDir(id: id)
        let fm = FileManager.default
        var out: [String: String] = ["folder": dir.path]
        let candidates: [(String, String)] = [
            ("audio", MeetingFiles.mixedAudio),
            ("microphone_audio", MeetingFiles.micAudio),
            ("system_audio", MeetingFiles.systemAudio),
            ("microphone_pcm", MeetingFiles.micPCM),
            ("system_pcm", MeetingFiles.systemPCM),
            ("transcript_markdown", MeetingFiles.transcriptMarkdown),
            ("transcript_json", MeetingFiles.transcriptJSON),
            ("metadata", MeetingFiles.metadata),
        ]
        for (key, file) in candidates {
            let p = dir.appendingPathComponent(file).path
            if fm.fileExists(atPath: p) { out[key] = p }
        }
        return out
    }

    // MARK: Search

    public struct SearchHit: Codable, Equatable, Sendable {
        public let kind: String
        /// Dictation UUID or meeting id.
        public let id: String
        public let timestamp: Date
        /// Seconds into the meeting (meetings only).
        public let offsetSeconds: Double?
        public let text: String
    }

    /// Case-insensitive substring search across dictations and meeting segments. Newest first.
    public func search(_ query: String, limit: Int = 50) -> [SearchHit] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        var hits: [SearchHit] = dictations(query: q).map {
            SearchHit(kind: "dictation", id: $0.id.uuidString, timestamp: $0.timestamp, offsetSeconds: nil, text: $0.text)
        }
        for meta in meetings() {
            guard let t = transcript(id: meta.id) else { continue }
            for seg in t.segments where seg.text.localizedCaseInsensitiveContains(q) {
                hits.append(SearchHit(
                    kind: "meeting",
                    id: meta.id,
                    timestamp: meta.startedAt.addingTimeInterval(seg.start),
                    offsetSeconds: seg.start,
                    text: seg.text
                ))
            }
        }
        hits.sort { $0.timestamp > $1.timestamp }
        return Array(hits.prefix(max(0, limit)))
    }
}

/// Parses `--since` values: ISO 8601 dates, `yyyy-MM-dd`, or relative `30m` / `24h` / `7d` / `2w`.
public enum SinceParser {
    public static func parse(_ raw: String, now: Date = Date()) -> Date? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !s.isEmpty else { return nil }
        if let unit = s.last, let n = Double(s.dropLast()), n >= 0 {
            let mult: Double?
            switch unit {
            case "m": mult = 60
            case "h": mult = 3600
            case "d": mult = 86_400
            case "w": mult = 7 * 86_400
            default: mult = nil
            }
            if let mult { return now.addingTimeInterval(-n * mult) }
        }
        let iso = ISO8601DateFormatter()
        if let d = iso.date(from: raw) { return d }
        let day = DateFormatter()
        day.locale = Locale(identifier: "en_US_POSIX")
        day.dateFormat = "yyyy-MM-dd"
        return day.date(from: raw)
    }
}

/// `AGENTS.md` the app writes into the data folder so agents that browse files find the layout.
public enum AgentDataReadme {
    public static func content(paths: MacWisprPaths, cliPath: String?) -> String {
        let cli = cliPath ?? "/Applications/MacWispr.app/Contents/Helpers/macwispr"
        return """
        # MacWispr data (for AI agents)

        This folder holds MacWispr's local dictation history and meeting recordings.
        Everything is read-only for agents: do not edit or delete files here unless the user asks.

        ## Command-line tool

        `\(cli)` (also `macwispr` on PATH if the user installed it from MacWispr → Meetings).

        ```
        macwispr history [--limit N] [--since 7d|24h|2026-10-01] [--search TEXT] [--json]
        macwispr meetings [--limit N] [--json]
        macwispr meeting <id|latest> [--json] [--files]
        macwispr search <TEXT> [--limit N] [--json]
        macwispr paths
        macwispr mcp          # MCP server over stdio
        ```

        MCP config: `{"mcpServers": {"macwispr": {"command": "\(cli)", "args": ["mcp"]}}}`

        ## Files

        - `history.json` — dictations, newest first. Fields: `id`, `text`, `timestamp` (ISO 8601), `duration` (seconds of audio), `wordCount`.
        - `Meetings/<yyyy-MM-dd_HHmmss>/` — one folder per meeting:
          - `meeting.json` — title, `startedAt`, `durationSeconds`, `status` (recording | processing | done | failed | interrupted), sources.
          - `transcript.md` — readable transcript with `[hh:mm:ss]` timestamps. "Me" = microphone, "Others" = system audio from other apps.
          - `transcript.json` — `segments[]` with `start`/`end` seconds, `source` (microphone | system), `text`.
          - `audio.m4a` — microphone and system audio mixed. `mic.m4a` / `system.m4a` — each side alone.
          - `mic.pcm` / `system.pcm` — raw 16 kHz mono 16-bit PCM, only while recording or processing.

        Data root: `\(paths.root.path)`
        """
    }
}
