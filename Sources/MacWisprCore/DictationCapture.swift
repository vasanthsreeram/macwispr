import Foundation

/// Gives every dictation its own `SampleRing`.
///
/// Starting a session swaps in a fresh ring instead of resetting the shared
/// one, so a previous dictation that is still transcribing keeps its audio and
/// its cleanup can only clear its own ring.
public final class CaptureSessionRings: @unchecked Sendable {
    private let lock = NSLock()
    private let makeRing: () -> SampleRing
    private var ring: SampleRing

    public init(makeRing: @escaping () -> SampleRing = { SampleRing() }) {
        self.makeRing = makeRing
        self.ring = makeRing()
    }

    /// Ring of the newest session (live partials, cancel, release).
    public var current: SampleRing {
        lock.lock()
        defer { lock.unlock() }
        return ring
    }

    /// Swap in a fresh ring for a new dictation. The old ring is left untouched.
    @discardableResult
    public func beginSession() -> SampleRing {
        let fresh = makeRing()
        lock.lock()
        ring = fresh
        lock.unlock()
        return fresh
    }

    /// Free one session's audio. Never touches a newer session's ring.
    public func clear(_ sessionRing: SampleRing) {
        sessionRing.reset()
    }
}

/// A dictation start queued behind a local-model reload (idle or memory-pressure unload).
///
/// Key-up or Esc before the reload finishes cancels the start, so the mic never
/// opens with no key held.
public struct PendingDictationStart: Equatable, Sendable {
    /// A reload kicked off by a start request is in flight.
    public private(set) var isReloading = false
    /// The user still wants recording to begin once the reload lands.
    public private(set) var wantsStart = false

    public init() {}

    /// Records a start request. Returns true when the caller must begin the reload
    /// (false while one is already in flight; the request still re-arms the start).
    public mutating func request() -> Bool {
        wantsStart = true
        if isReloading { return false }
        isReloading = true
        return true
    }

    /// Key-up / Esc / toggle-off before the reload finished. Returns true if a
    /// pending start was dropped.
    @discardableResult
    public mutating func cancel() -> Bool {
        let had = wantsStart
        wantsStart = false
        return had
    }

    /// Call when the reload ends. Returns true when recording should start now.
    public mutating func reloadFinished(modelLoaded: Bool, isRecording: Bool) -> Bool {
        let start = wantsStart && modelLoaded && !isRecording
        isReloading = false
        wantsStart = false
        return start
    }
}

/// Picks the Core Audio input device the dictation engine must bind.
public enum InputDeviceResolver {
    /// - Parameters:
    ///   - requestedUID: saved UID; nil / blank means "System Default".
    ///   - available: live input devices, UID → `AudioDeviceID`.
    ///   - defaultDeviceID: current system default input.
    /// - Returns: the device to bind, or nil when there is nothing to bind.
    ///   nil, blank and unknown (unplugged) UIDs resolve to the default, so the
    ///   long-lived engine never stays on a previously chosen device.
    public static func deviceToBind(
        requestedUID: String?,
        available: [String: UInt32],
        defaultDeviceID: UInt32?
    ) -> UInt32? {
        let uid = requestedUID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !uid.isEmpty, let id = available[uid] {
            return id
        }
        return defaultDeviceID
    }
}

/// What the dictation recorder does when its `AVAudioEngine` reports a
/// configuration change (device unplugged, default input switched, sample rate changed).
public enum CaptureConfigurationChange {
    public enum Action: Equatable, Sendable {
        /// Not recording: the next start rebuilds the graph anyway.
        case ignore
        /// Recording: rebuild tap + converter for the new format and keep
        /// appending to the same session ring.
        case restartIntoSessionRing
        /// Recording, but restarts keep failing or looping: close the mic and
        /// finish with the audio captured so far.
        case stop
    }

    /// Guards against a device that posts a change on every engine start.
    public static let maxRestartsPerSession = 5

    public static func action(isCapturing: Bool, restartsThisSession: Int) -> Action {
        guard isCapturing else { return .ignore }
        return restartsThisSession < maxRestartsPerSession ? .restartIntoSessionRing : .stop
    }

    /// Whether an input format can be captured from (no device / no permission → false).
    public static func canCapture(sampleRate: Double, channelCount: Int) -> Bool {
        sampleRate > 0 && channelCount > 0
    }
}
