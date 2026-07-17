import AppKit
import Foundation

/// Opt-in **local** dictation capture for debugging (audio + text stages).
///
/// - Off by default.
/// - Writes only under Application Support — never telemetry / network.
/// - Env override: `MACWISPR_DEV_CAPTURE=1` forces on for a process lifetime.
enum DevCaptureStore {
    static let maxCaptures = 100
    private static let folderName = "dev-captures"
    private static let prefsKey = "devCaptureEnabled"

    /// UserDefaults + env. Env wins for one-off CLI / agent runs.
    static var isEnabled: Bool {
        if ProcessInfo.processInfo.environment["MACWISPR_DEV_CAPTURE"] == "1" {
            return true
        }
        return UserDefaults.standard.bool(forKey: prefsKey)
    }

    static func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: prefsKey)
    }

    static var rootDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base
            .appendingPathComponent("MacWispr", isDirectory: true)
            .appendingPathComponent(folderName, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// One capture per dictation: `audio.wav` + `meta.json`.
    @discardableResult
    static func save(
        samples: [Float],
        sampleRate: Int = 16_000,
        entryId: UUID?,
        rawSTT: String?,
        afterPostProcess: String?,
        polished: String?,
        audioDuration: Double,
        sttLatency: Double?,
        transcriptionProvider: String,
        asrModel: String?,
        polishProvider: String,
        polishModel: String?,
        error: String? = nil
    ) -> URL? {
        guard isEnabled else { return nil }
        guard !samples.isEmpty || rawSTT != nil || polished != nil || error != nil else { return nil }

        let fm = FileManager.default
        let stamp = Self.fileStamp(Date())
        let shortId = (entryId ?? UUID()).uuidString.prefix(8)
        let dir = rootDirectory.appendingPathComponent("\(stamp)_\(shortId)", isDirectory: true)
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            NSLog("MacWispr dev capture: mkdir failed: \(error.localizedDescription)")
            return nil
        }

        if !samples.isEmpty {
            let wav = AudioWAVEncoder.encode(samples: samples, sampleRate: sampleRate)
            let wavURL = dir.appendingPathComponent("audio.wav")
            do {
                try wav.write(to: wavURL, options: .atomic)
            } catch {
                NSLog("MacWispr dev capture: wav write failed: \(error.localizedDescription)")
            }
        }

        var meta: [String: Any] = [
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "audioDurationSec": audioDuration,
            "sampleCount": samples.count,
            "sampleRate": sampleRate,
            "transcriptionProvider": transcriptionProvider,
            "polishProvider": polishProvider,
            "appVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?",
        ]
        if let entryId { meta["id"] = entryId.uuidString }
        if let sttLatency { meta["sttLatencySec"] = sttLatency }
        if let asrModel { meta["asrModel"] = asrModel }
        if let polishModel { meta["polishModel"] = polishModel }
        if let rawSTT { meta["rawSTT"] = rawSTT }
        if let afterPostProcess { meta["afterPostProcess"] = afterPostProcess }
        if let polished { meta["polished"] = polished }
        if let error { meta["error"] = error }

        // Also write plain text files for quick diff in Finder / terminal.
        writeText(rawSTT, name: "01_raw_stt.txt", in: dir)
        writeText(afterPostProcess, name: "02_postprocess.txt", in: dir)
        writeText(polished, name: "03_polished.txt", in: dir)

        if let data = try? JSONSerialization.data(withJSONObject: meta, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: dir.appendingPathComponent("meta.json"), options: .atomic)
        }

        pruneOldCaptures()
        NSLog("MacWispr dev capture: saved \(dir.path)")
        return dir
    }

    static func openInFinder() {
        NSWorkspace.shared.open(rootDirectory)
    }

    static func captureCount() -> Int {
        let fm = FileManager.default
        guard let kids = try? fm.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        return kids.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }.count
    }

    static func clearAll() {
        let fm = FileManager.default
        guard let kids = try? fm.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }
        for url in kids {
            try? fm.removeItem(at: url)
        }
    }

    // MARK: - Private

    private static func writeText(_ text: String?, name: String, in dir: URL) {
        guard let text, !text.isEmpty else { return }
        try? text.write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    private static func fileStamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyyMMdd_HHmmss"
        return f.string(from: date)
    }

    private static func pruneOldCaptures() {
        let fm = FileManager.default
        guard let kids = try? fm.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: [.creationDateKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let dirs = kids.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
        guard dirs.count > maxCaptures else { return }

        let sorted = dirs.sorted { a, b in
            let da = (try? a.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            let db = (try? b.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return da > db // newest first
        }
        for stale in sorted.dropFirst(maxCaptures) {
            try? fm.removeItem(at: stale)
        }
    }
}
