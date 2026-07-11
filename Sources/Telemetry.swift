import Foundation
import AppKit

// MARK: - Privacy-first opt-in telemetry (PostHog HTTPS /capture)
//
// NEVER collect (stays private, on-device only):
// - Transcription text — ever
// - Audio samples or recordings
// - Custom vocabulary words
// - Clipboard contents
// - API keys / secrets
// - Hardware serials, MAC address, username, email, IP-derived identity, precise location
// - Raw timestamps/durations that could fingerprint (we bucket)
//
// Single choke point: every outbound analytics payload goes through Telemetry.shared.

/// Whitelisted event names only — no autocapture, no session recording.
enum TelemetryEventName: String {
    case hotkeyHealth = "hotkey_health"
    case dictationCompleted = "dictation_completed"
    case dictationFailed = "dictation_failed"
    case optIn = "opt_in"
    case optOut = "opt_out"
}

/// Failure categories for `dictation_failed` (enum only — no free text).
enum DictationFailureReason: String {
    case noAudio = "no_audio"
    case micDenied = "mic_denied"
    case pasteNoAX = "paste_no_ax"
    case sttError = "stt_error"
}

/// Coarse insertion result for `dictation_completed`.
enum TelemetryInsertionOutcome: String {
    case ok
    case clipboardOnly = "clipboard_only"
    case failed
}

/// Privacy-first, opt-in, anonymous telemetry client.
///
/// Transport is raw HTTPS to PostHog's `/batch` endpoint — no SDK dependency.
/// When the opt-in flag is off, `capture` is a hard no-op.
final class Telemetry: @unchecked Sendable {
    static let shared = Telemetry()

    // PostHog project API key (client write key — safe to embed; not a personal/secret key).
    // Project: Default project (id 157741) on us.posthog.com
    private static let postHogAPIKey = "phc_Hy1J2gWvIB7PHg32igMdmwAjXjTlkEXbw8vWW9Nr0zj"
    private static let postHogBatchURL = URL(string: "https://us.i.posthog.com/batch/")!

    private static let installIDKey = "telemetryInstallID"
    private static let optInKey = "telemetryOptIn"
    private static let disclosureSeenKey = "telemetryDisclosureSeen"

    private let queue = DispatchQueue(label: "com.macwispr.telemetry", qos: .utility)
    private var pending: [[String: Any]] = []
    private var lastHotkeyHealthFingerprint: String?
    private var flushWorkItem: DispatchWorkItem?
    /// Minimum interval between spontaneous flushes (batched fire-and-forget).
    private let flushDebounceSeconds: TimeInterval = 8
    private let maxBatchSize = 20

    private init() {
        // Ensure install ID exists even when opted out (stable across enable).
        _ = installID
    }

    // MARK: - Opt-in kill-switch

    /// Global kill-switch. Default OFF (opt-in). When false, `capture` is a no-op.
    var isOptedIn: Bool {
        UserDefaults.standard.bool(forKey: Self.optInKey)
    }

    /// Whether the first-run disclosure sheet has been acknowledged.
    var hasSeenDisclosure: Bool {
        UserDefaults.standard.bool(forKey: Self.disclosureSeenKey)
    }

    func markDisclosureSeen() {
        UserDefaults.standard.set(true, forKey: Self.disclosureSeenKey)
    }

    /// Enable or disable telemetry. Toggling off sends a final `opt_out` then mutes.
    func setOptIn(_ enabled: Bool) {
        let wasEnabled = isOptedIn
        if enabled == wasEnabled {
            UserDefaults.standard.set(enabled, forKey: Self.optInKey)
            return
        }

        if enabled {
            UserDefaults.standard.set(true, forKey: Self.optInKey)
            markDisclosureSeen()
            // Clear dedupe so the next health snapshot can fire after re-opt-in.
            queue.async { [weak self] in
                self?.lastHotkeyHealthFingerprint = nil
            }
            capture(.optIn, properties: [:])
            flush(force: true)
        } else if wasEnabled {
            // Enqueue final opt_out + force flush on the serial queue *before* muting
            // so the kill-switch doesn't drop the last event.
            let optOutPayload = makeEventPayload(event: TelemetryEventName.optOut.rawValue, properties: [:])
            queue.async { [weak self] in
                guard let self else { return }
                self.pending.append(optOutPayload)
                self.flushLocked(force: true)
                self.pending.removeAll()
                self.flushWorkItem?.cancel()
                self.flushWorkItem = nil
                self.lastHotkeyHealthFingerprint = nil
            }
            UserDefaults.standard.set(false, forKey: Self.optInKey)
        } else {
            UserDefaults.standard.set(false, forKey: Self.optInKey)
        }
    }

    private func makeEventPayload(event: String, properties: [String: Any]) -> [String: Any] {
        var props = baseProperties()
        for (key, value) in properties {
            if let s = value as? String, s.count > 200 { continue }
            props[key] = value
        }
        return [
            "event": event,
            "distinct_id": installID,
            "properties": props,
            "timestamp": iso8601Now(),
        ]
    }

    // MARK: - Anonymous install ID

    /// Random UUID generated once, persisted in UserDefaults. Never a hardware ID.
    var installID: String {
        if let existing = UserDefaults.standard.string(forKey: Self.installIDKey), !existing.isEmpty {
            return existing
        }
        let id = UUID().uuidString.lowercased()
        UserDefaults.standard.set(id, forKey: Self.installIDKey)
        return id
    }

    // MARK: - Capture (whitelisted events only)

    /// Enqueue a whitelisted event. No-op when opted out. Never throws; never blocks callers.
    func capture(_ event: TelemetryEventName, properties: [String: Any] = [:]) {
        capture(event.rawValue, properties: properties)
    }

    /// String-based capture restricted to known event names.
    func capture(_ event: String, properties: [String: Any] = [:]) {
        guard isOptedIn else { return }
        guard TelemetryEventName(rawValue: event) != nil else {
            #if DEBUG
            NSLog("MacWispr telemetry: dropped non-whitelisted event %@", event)
            #endif
            return
        }

        let payload = makeEventPayload(event: event, properties: properties)

        queue.async { [weak self] in
            guard let self else { return }
            self.pending.append(payload)
            if self.pending.count >= self.maxBatchSize {
                self.flushLocked(force: true)
            } else {
                self.scheduleFlushLocked()
            }
        }
    }

    // MARK: - Hotkey health (#8)

    /// Emit `hotkey_health` only when the boolean snapshot changes (or first send).
    func reportHotkeyHealth(
        tapInstalled: Bool,
        carbonInstalled: Bool,
        axTrusted: Bool,
        armed: Bool
    ) {
        guard isOptedIn else { return }
        let fingerprint = "\(tapInstalled)|\(carbonInstalled)|\(axTrusted)|\(armed)"
        queue.async { [weak self] in
            guard let self else { return }
            if self.lastHotkeyHealthFingerprint == fingerprint { return }
            self.lastHotkeyHealthFingerprint = fingerprint
            // capture() re-checks opt-in and hops back onto the queue — fine for volume.
            DispatchQueue.main.async {
                self.capture(.hotkeyHealth, properties: [
                    "tap_installed": tapInstalled,
                    "carbon_installed": carbonInstalled,
                    "ax_trusted": axTrusted,
                    "armed": armed,
                ])
            }
        }
    }

    // MARK: - Dictation lifecycle (#9)

    func reportDictationCompleted(
        provider: String,
        modelSize: String,
        mode: String,
        insertionMode: String,
        sttLatencySeconds: TimeInterval,
        audioDurationSeconds: TimeInterval,
        insertionOutcome: TelemetryInsertionOutcome
    ) {
        capture(.dictationCompleted, properties: [
            "provider": provider,
            "model_size": modelSize,
            "mode": mode,
            "insertion_mode": insertionMode,
            "stt_latency_bucket": Self.sttLatencyBucket(sttLatencySeconds),
            "duration_bucket": Self.durationBucket(audioDurationSeconds),
            "insertion_outcome": insertionOutcome.rawValue,
        ])
    }

    func reportDictationFailed(reason: DictationFailureReason) {
        capture(.dictationFailed, properties: [
            "reason": reason.rawValue,
        ])
    }

    // MARK: - Buckets (never raw timings)

    static func sttLatencyBucket(_ seconds: TimeInterval) -> String {
        if seconds < 1 { return "<1s" }
        if seconds < 3 { return "1-3s" }
        if seconds < 10 { return "3-10s" }
        return ">10s"
    }

    /// Coarse audio-length buckets — not precise enough to fingerprint.
    static func durationBucket(_ seconds: TimeInterval) -> String {
        if seconds < 2 { return "<2s" }
        if seconds < 5 { return "2-5s" }
        if seconds < 15 { return "5-15s" }
        if seconds < 30 { return "15-30s" }
        return ">30s"
    }

    // MARK: - Flush

    /// Send pending events. Safe on background/quit; failures are dropped silently.
    func flush(force: Bool = false) {
        queue.async { [weak self] in
            self?.flushLocked(force: force)
        }
    }

    private func scheduleFlushLocked() {
        flushWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.flushLocked(force: false)
        }
        flushWorkItem = work
        queue.asyncAfter(deadline: .now() + flushDebounceSeconds, execute: work)
    }

    private func flushLocked(force: Bool) {
        flushWorkItem?.cancel()
        flushWorkItem = nil
        guard !pending.isEmpty else { return }
        // If user opted out mid-batch (except the final opt_out already enqueued), drop.
        // We still send whatever is already queued when force-flushing opt_out.
        if !isOptedIn && !force {
            pending.removeAll()
            return
        }

        let batch = pending
        pending.removeAll()

        let body: [String: Any] = [
            "api_key": Self.postHogAPIKey,
            "batch": batch,
            "historical_migration": false,
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return }

        var request = URLRequest(url: Self.postHogBatchURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        request.timeoutInterval = 15

        // Fire-and-forget — never surface errors to the app.
        URLSession.shared.dataTask(with: request) { _, _, _ in
            // Drop on failure intentionally (fail-silent).
        }.resume()
    }

    // MARK: - Base properties

    private func baseProperties() -> [String: Any] {
        [
            "distinct_id": installID,
            "install_id": installID,
            "app_version": AppVersion.display,
            "macos_version": ProcessInfo.processInfo.operatingSystemVersionString,
            "arch": Self.cpuArchitecture,
            // Disable any PostHog product features that might otherwise activate server-side.
            "$geoip_disable": true,
            "$ip": "0.0.0.0",
            "$lib": "macwispr-native",
            "$lib_version": AppVersion.display,
        ]
    }

    private static var cpuArchitecture: String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown"
        #endif
    }

    private func iso8601Now() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}
