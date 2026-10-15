import Foundation

/// Splits a long recording into speech regions so a meeting is transcribed in
/// short pieces with real timestamps, and silent stretches never reach the model.
public enum MeetingSegmenter {
    public static let frameSamples = 480 // 30 ms at 16 kHz

    public struct Config: Equatable, Sendable {
        public var sampleRate = 16_000
        /// Speech must be this many dB above the recording's noise floor.
        public var marginDB: Float = 9
        /// Never treat anything quieter than this as speech.
        public var absoluteFloorDB: Float = -50
        /// Anything louder than this is speech, even when the "noise floor" is high
        /// (back-to-back talking all recording, or a noisy room). Errs toward transcribing.
        public var ceilingDB: Float = -35
        /// Pauses shorter than this stay inside one region.
        public var mergeGapSeconds: Double = 0.6
        /// Regions with less speech than this are dropped (clicks, coughs).
        public var minSpeechSeconds: Double = 0.3
        /// Soft word onsets sit below the threshold; 0.25 s clipped "Quarterly" to "Orderly".
        public var padSeconds: Double = 0.5
        /// Longer regions are cut at the quietest point before this length.
        /// Below the Parakeet window (28 s) so each region is one model pass.
        public var maxRegionSeconds: Double = 24
        /// How far back from `maxRegionSeconds` to look for a quiet cut point.
        public var cutSearchSeconds: Double = 8

        public init() {}
    }

    /// Per-frame loudness in dBFS.
    public static func frameLevels(_ samples: UnsafeBufferPointer<Float>) -> [Float] {
        let n = samples.count / frameSamples
        var out = [Float](repeating: -120, count: n)
        for f in 0..<n {
            var sum: Float = 0
            let base = f * frameSamples
            for i in 0..<frameSamples {
                let v = samples[base + i]
                sum += v * v
            }
            let rms = (sum / Float(frameSamples)).squareRoot()
            out[f] = 20 * log10(max(rms, 1e-6))
        }
        return out
    }

    public static func frameLevels(_ samples: [Float]) -> [Float] {
        samples.withUnsafeBufferPointer { frameLevels($0) }
    }

    /// Streams a PCM file in 30 s blocks so an hour-long track never sits in RAM.
    public static func frameLevels(_ reader: PCM16FileReader) -> [Float] {
        let block = frameSamples * 1000
        var out: [Float] = []
        out.reserveCapacity(reader.sampleCount / frameSamples)
        var start = 0
        while start < reader.sampleCount {
            let chunk = reader.read(start: start, count: min(block, reader.sampleCount - start))
            if chunk.isEmpty { break }
            out.append(contentsOf: frameLevels(chunk))
            start += chunk.count
        }
        return out
    }

    /// Speech regions as sample ranges, in order, non-overlapping.
    public static func regions(levels: [Float], totalSamples: Int, config: Config = Config()) -> [Range<Int>] {
        guard !levels.isEmpty, totalSamples > 0 else { return [] }
        let threshold = min(max(noiseFloor(levels) + config.marginDB, config.absoluteFloorDB), config.ceilingDB)
        let frameSec = Double(frameSamples) / Double(config.sampleRate)
        let mergeGap = Int((config.mergeGapSeconds / frameSec).rounded())
        let minSpeech = Int((config.minSpeechSeconds / frameSec).rounded())

        // Runs of loud frames, merged across short pauses.
        var runs: [(start: Int, end: Int, speech: Int)] = []
        var f = 0
        while f < levels.count {
            guard levels[f] > threshold else { f += 1; continue }
            var end = f
            while end < levels.count, levels[end] > threshold { end += 1 }
            let count = end - f
            if var last = runs.last, f - last.end <= mergeGap {
                last.end = end
                last.speech += count
                runs[runs.count - 1] = last
            } else {
                runs.append((f, end, count))
            }
            f = end
        }

        let pad = Int(config.padSeconds * Double(config.sampleRate))
        let maxLen = Int(config.maxRegionSeconds * Double(config.sampleRate))
        let search = Int(config.cutSearchSeconds * Double(config.sampleRate))
        var out: [Range<Int>] = []
        for run in runs where run.speech >= minSpeech {
            var start = max(0, run.start * frameSamples - pad)
            let end = min(totalSamples, run.end * frameSamples + pad)
            if let last = out.last, start < last.upperBound {
                start = last.upperBound
            }
            guard start < end else { continue }
            out.append(contentsOf: split(start..<end, levels: levels, maxLen: maxLen, search: search))
        }
        return out
    }

    /// Cuts a long region at the quietest frame in the last `search` samples of each piece.
    static func split(_ range: Range<Int>, levels: [Float], maxLen: Int, search: Int) -> [Range<Int>] {
        var out: [Range<Int>] = []
        var start = range.lowerBound
        while range.upperBound - start > maxLen {
            let hardEnd = start + maxLen
            let lo = max(start + maxLen / 2, hardEnd - search) / frameSamples
            let hi = hardEnd / frameSamples
            var cutFrame = hi
            var quietest = Float.greatestFiniteMagnitude
            if lo < hi {
                for fr in lo..<min(hi, levels.count) where levels[fr] < quietest {
                    quietest = levels[fr]
                    cutFrame = fr
                }
            }
            let cut = max(start + 1, min(hardEnd, cutFrame * frameSamples))
            out.append(start..<cut)
            start = cut
        }
        if start < range.upperBound { out.append(start..<range.upperBound) }
        return out
    }

    /// Low percentile of frame levels, ignoring digital silence.
    static func noiseFloor(_ levels: [Float]) -> Float {
        let live = levels.filter { $0 > -110 }
        guard !live.isEmpty else { return -120 }
        let sorted = live.sorted()
        return sorted[min(sorted.count - 1, sorted.count / 10)]
    }
}

/// Merges microphone and system-audio segments and drops microphone segments
/// that are only the speakers leaking into the mic (no headphones).
public enum MeetingMerge {
    public static func merge(_ segments: [MeetingSegment], echoThreshold: Double = 0.6) -> [MeetingSegment] {
        let cleaned = segments
            .map { seg -> MeetingSegment in
                var s = seg
                s.text = seg.text.trimmingCharacters(in: .whitespacesAndNewlines)
                return s
            }
            .filter { !$0.text.isEmpty }
        let system = cleaned.filter { $0.source == .system }
        let kept = cleaned.filter { seg in
            guard seg.source == .microphone, !system.isEmpty else { return true }
            return !isEcho(seg, system: system, threshold: echoThreshold)
        }
        return kept.sorted { ($0.start, $0.source == .microphone ? 0 : 1) < ($1.start, $1.source == .microphone ? 0 : 1) }
    }

    /// True when most of a mic segment's words appear in system audio heard at the same time.
    static func isEcho(_ mic: MeetingSegment, system: [MeetingSegment], threshold: Double) -> Bool {
        let slack = 1.5
        let overlapping = system.filter { $0.end + slack > mic.start && $0.start - slack < mic.end }
        guard !overlapping.isEmpty else { return false }
        let micWords = TranscriptStitch.words(mic.text).map(TranscriptStitch.matchKey).filter { !$0.isEmpty }
        guard !micWords.isEmpty else { return true }
        let sysWords = Set(overlapping.flatMap { TranscriptStitch.words($0.text).map(TranscriptStitch.matchKey) })
        let shared = micWords.filter { sysWords.contains($0) }.count
        return Double(shared) / Double(micWords.count) >= threshold
    }
}
