import Foundation

/// Keeps meeting tracks on one 16 kHz timeline. Time is measured on the awake
/// clock, so hours the Mac spends asleep are skipped instead of padded with silence.
public enum MeetingTimeline {
    public static let sampleRate = 16_000
    /// Gaps shorter than this are buffering jitter, not a stall.
    public static let padThresholdSamples = 8_000
    /// Drop-outs at least this long are reported on the meeting.
    public static let stallWarningSamples = 5 * 16_000

    /// Seconds the Mac has been awake. Does not advance during sleep (unlike `Date()`).
    public static func awakeNow() -> TimeInterval {
        ProcessInfo.processInfo.systemUptime
    }

    public static func elapsedSamples(since start: TimeInterval, now: TimeInterval) -> Int {
        max(0, Int((now - start) * Double(sampleRate)))
    }

    /// Silence to write before `incoming` new samples so the track ends at `elapsedSamples`.
    public static func silenceToPad(elapsedSamples: Int, written: Int, incoming: Int) -> Int {
        let gap = elapsedSamples - incoming - written
        return gap > padThresholdSamples ? gap : 0
    }

    /// Warning for a drop-out that was later filled with silence, or nil if it was short.
    public static func stallWarning(track: String, gapSamples: Int, atSample: Int) -> String? {
        guard gapSamples >= stallWarningSamples else { return nil }
        let seconds = Int((Double(gapSamples) / Double(sampleRate)).rounded())
        let at = UsageClock.format(seconds: Double(atSample) / Double(sampleRate))
        return "\(track) dropped out for \(seconds) s at \(at) (audio device change?). That part is silent."
    }

    /// Warning for a track that stopped delivering audio before the meeting ended.
    public static func trailingStallWarning(track: String, elapsedSamples: Int, written: Int) -> String? {
        let missing = elapsedSamples - written
        guard missing >= stallWarningSamples else { return nil }
        let length = UsageClock.format(seconds: Double(missing) / Double(sampleRate))
        return "\(track) stopped recording \(length) before the end of the meeting."
    }
}

/// Free-space check before a meeting starts. Raw tracks are 16 kHz 16-bit mono.
public enum MeetingDiskSpace: Equatable {
    case ok
    /// Enough to start, but only about `minutes` of recording fit.
    case low(minutes: Int)
    /// Too little space to record anything useful.
    case insufficient(minutes: Int)

    public static let bytesPerTrackSecond: Int64 = Int64(MeetingTimeline.sampleRate) * 2
    public static let refuseBelowMinutes = 10
    public static let warnBelowMinutes = 120

    /// `availableBytes` nil (unknown) never blocks recording.
    public static func check(availableBytes: Int64?, tracks: Int) -> MeetingDiskSpace {
        guard let availableBytes, tracks > 0 else { return .ok }
        let minutes = Int(availableBytes / (bytesPerTrackSecond * Int64(tracks) * 60))
        if minutes < refuseBelowMinutes { return .insufficient(minutes: minutes) }
        if minutes < warnBelowMinutes { return .low(minutes: minutes) }
        return .ok
    }
}
