import Foundation

/// One overlapping window over a 16 kHz PCM capture.
public struct AudioChunkWindow: Equatable, Sendable {
    public let startSample: Int
    public let endSample: Int

    public var count: Int { endSample - startSample }

    public init(startSample: Int, endSample: Int) {
        self.startSample = startSample
        self.endSample = endSample
    }
}

/// Bounded windows so ASR / cloud APIs never see an hour-long buffer at once.
public enum AudioChunkPlanner {
    public static let sampleRate = 16_000

    /// Qwen batch is token-capped; ~30 s is accurate and GPU-bounded.
    public static let qwenWindowSamples = 30 * sampleRate
    public static let qwenOverlapSamples = 2 * sampleRate

    /// Parakeet INT8 encoder is a fixed ~30 s mel window — stay under it.
    public static let parakeetWindowSamples = 28 * sampleRate
    public static let parakeetOverlapSamples = 2 * sampleRate

    /// OpenAI transcriptions ~25 MB cap. 10 min 16 kHz 16-bit WAV ≈ 19 MB.
    public static let cloudWindowSamples = 10 * 60 * sampleRate
    public static let cloudOverlapSamples = 2 * sampleRate

    public static func windows(
        sampleCount: Int,
        windowSamples: Int,
        overlapSamples: Int
    ) -> [AudioChunkWindow] {
        let n = max(0, sampleCount)
        guard n > 0 else { return [] }
        let window = max(1, windowSamples)
        let overlap = min(max(0, overlapSamples), window - 1)
        let step = window - overlap

        if n <= window {
            return [AudioChunkWindow(startSample: 0, endSample: n)]
        }

        // Every adjacent pair overlaps by exactly `overlap` samples: stitching
        // only de-duplicates a short word run, so a wider overlap repeats speech.
        // The last window may be shorter; it still overlaps the previous one.
        var result: [AudioChunkWindow] = []
        var start = 0
        while start < n {
            let end = min(start + window, n)
            result.append(AudioChunkWindow(startSample: start, endSample: end))
            if end >= n { break }
            start += step
        }
        return result
    }

    /// Decoder budget for one window. ~2.5 words/s × ~2 tokens/word, floored.
    public static func maxTokens(forSampleCount sampleCount: Int, cap: Int = 512) -> Int {
        let seconds = Double(max(0, sampleCount)) / Double(sampleRate)
        let estimate = Int((seconds * 6.0).rounded(.up))
        return min(cap, max(64, estimate))
    }
}
