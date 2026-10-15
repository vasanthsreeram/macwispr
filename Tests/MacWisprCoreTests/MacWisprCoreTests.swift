import XCTest
@testable import MacWisprCore

final class AudioChunkPlannerTests: XCTestCase {
    func testShortClipIsSingleWindow() {
        let windows = AudioChunkPlanner.windows(
            sampleCount: 16_000,
            windowSamples: AudioChunkPlanner.qwenWindowSamples,
            overlapSamples: AudioChunkPlanner.qwenOverlapSamples
        )
        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual(windows[0].startSample, 0)
        XCTAssertEqual(windows[0].endSample, 16_000)
    }

    func testEmptyIsNoWindows() {
        XCTAssertTrue(
            AudioChunkPlanner.windows(sampleCount: 0, windowSamples: 100, overlapSamples: 10).isEmpty
        )
    }

    func testHourLongQwenStaysWindowSized() {
        let hour = 60 * 60 * AudioChunkPlanner.sampleRate
        let windows = AudioChunkPlanner.windows(
            sampleCount: hour,
            windowSamples: AudioChunkPlanner.qwenWindowSamples,
            overlapSamples: AudioChunkPlanner.qwenOverlapSamples
        )
        XCTAssertGreaterThan(windows.count, 100)
        XCTAssertEqual(windows.first?.startSample, 0)
        XCTAssertEqual(windows.last?.endSample, hour)
        for w in windows {
            XCTAssertLessThanOrEqual(w.count, AudioChunkPlanner.qwenWindowSamples)
            XCTAssertGreaterThan(w.count, 0)
        }
        // Adjacent windows overlap so stitch can drop duplicated tail words.
        for i in 1..<windows.count {
            XCTAssertLessThan(windows[i].startSample, windows[i - 1].endSample)
        }
    }

    func testParakeetWindowsStayUnderEncoder() {
        let samples = 95 * AudioChunkPlanner.sampleRate
        let windows = AudioChunkPlanner.windows(
            sampleCount: samples,
            windowSamples: AudioChunkPlanner.parakeetWindowSamples,
            overlapSamples: AudioChunkPlanner.parakeetOverlapSamples
        )
        XCTAssertGreaterThanOrEqual(windows.count, 4)
        for w in windows {
            XCTAssertLessThanOrEqual(w.count, AudioChunkPlanner.parakeetWindowSamples)
        }
        XCTAssertEqual(windows.last?.endSample, samples)
    }

    /// Overlap must stay at the configured 2 s for every pair, including the
    /// last window. A tail snapped back to a full window re-transcribed up to
    /// 26 s twice and the word-level stitch could not remove it.
    func testOverlapNeverExceedsConfigured() {
        let sr = AudioChunkPlanner.sampleRate
        for seconds in [29, 30, 35, 45, 60, 90, 181] {
            let windows = AudioChunkPlanner.windows(
                sampleCount: seconds * sr,
                windowSamples: AudioChunkPlanner.parakeetWindowSamples,
                overlapSamples: AudioChunkPlanner.parakeetOverlapSamples
            )
            XCTAssertEqual(windows.first?.startSample, 0)
            XCTAssertEqual(windows.last?.endSample, seconds * sr)
            for i in 1..<windows.count {
                let overlap = windows[i - 1].endSample - windows[i].startSample
                XCTAssertEqual(overlap, AudioChunkPlanner.parakeetOverlapSamples, "\(seconds)s window \(i)")
            }
        }
    }

    func testMaxTokensIsPerWindowNotFullHour() {
        let hour = 60 * 60 * AudioChunkPlanner.sampleRate
        let hourTokens = AudioChunkPlanner.maxTokens(forSampleCount: hour, cap: 256)
        XCTAssertEqual(hourTokens, 256)

        let thirty = 30 * AudioChunkPlanner.sampleRate
        let windowTokens = AudioChunkPlanner.maxTokens(forSampleCount: thirty, cap: 512)
        XCTAssertGreaterThan(windowTokens, 64)
        XCTAssertLessThanOrEqual(windowTokens, 512)
    }
}

final class TranscriptStitchTests: XCTestCase {
    func testDropsOverlappingWordPrefix() {
        let joined = TranscriptStitch.join([
            "hello world this is a test",
            "this is a test of stitching",
        ])
        XCTAssertEqual(joined, "hello world this is a test of stitching")
    }

    func testOverlapIgnoresCaseAndPunctuation() {
        let joined = TranscriptStitch.join([
            "penetrating into obscure silences only to hear and",
            "Silences only to hear and feel the more deeply",
        ])
        XCTAssertEqual(joined, "penetrating into obscure silences only to hear and feel the more deeply")
    }

    func testEmptyPartsIgnored() {
        XCTAssertEqual(TranscriptStitch.join(["", "  hello  ", ""]), "hello")
    }

    func testPolishWordChunksBoundSize() {
        let words = (0..<400).map { "w\($0)" }.joined(separator: " ")
        let chunks = TextChunker.wordChunks(words, maxWords: 120, overlapWords: 8)
        XCTAssertGreaterThan(chunks.count, 2)
        XCTAssertEqual(TranscriptStitch.words(chunks[0]).count, 120)
        XCTAssertLessThanOrEqual(TranscriptStitch.words(chunks.last!).count, 120)
    }
}

final class GrokErrorClassifierTests: XCTestCase {
    func testQuotaStatus429() {
        XCTAssertEqual(GrokErrorClassifier.classify(status: 429, body: "nope"), .quota)
    }

    func testQuotaBodyEvenOnGeneric500() {
        let kind = GrokErrorClassifier.classify(
            status: 0,
            body: "resource_exhausted: weekly limit has been reached"
        )
        XCTAssertEqual(kind, .quota)
        XCTAssertTrue(
            GrokErrorClassifier.userMessage(for: kind).lowercased().contains("weekly limit")
        )
    }

    func testAuth() {
        XCTAssertEqual(
            GrokErrorClassifier.classify(status: 401, body: "unauthorized"),
            .auth
        )
    }

    func testEmptySpeech() {
        XCTAssertEqual(
            GrokErrorClassifier.classify(status: 0, body: "Grok STT: no speech detected"),
            .empty
        )
    }

    func testGenericServerDoesNotClaimQuota() {
        XCTAssertEqual(
            GrokErrorClassifier.classify(status: 0, body: "There was a bad response from the server."),
            .server
        )
    }
}

final class MemoryPressurePolicyTests: XCTestCase {
    func testNeverUnloadsWhileRecording() {
        let action = MemoryPressurePolicy.action(
            level: .critical,
            availableBytes: 1,
            asrLoaded: true,
            polishLoaded: true,
            recording: true
        )
        XCTAssertEqual(action, .keep)
    }

    func testCriticalUnloadsBoth() {
        let action = MemoryPressurePolicy.action(
            level: .critical,
            availableBytes: 8_000_000_000,
            asrLoaded: true,
            polishLoaded: true,
            recording: false
        )
        XCTAssertEqual(action, .unloadASRAndPolish)
    }

    func testWarningUnloadsPolishFirst() {
        let action = MemoryPressurePolicy.action(
            level: .warning,
            availableBytes: 4_000_000_000,
            asrLoaded: true,
            polishLoaded: true,
            recording: false
        )
        XCTAssertEqual(action, .unloadPolish)
    }

    func testRefuseLargeWhenTight() {
        XCTAssertFalse(MemoryPressurePolicy.canLoadLargeQwen(availableBytes: 1_000_000_000))
        XCTAssertTrue(MemoryPressurePolicy.canLoadLargeQwen(availableBytes: 6_000_000_000))
    }

    func testOOMStrings() {
        XCTAssertTrue(MemoryPressurePolicy.looksLikeOOM("Metal: out of memory"))
        XCTAssertTrue(MemoryPressurePolicy.looksLikeOOM("failed to allocate MTLBuffer"))
        XCTAssertFalse(MemoryPressurePolicy.looksLikeOOM("file couldn't be opened"))
    }
}

final class ProcessMemoryTests: XCTestCase {
    func testAvailableBytesProbe() {
        let bytes = ProcessMemory.availableBytes()
        XCTAssertNotNil(bytes)
        XCTAssertGreaterThan(bytes ?? 0, 1_000_000)
    }
}

final class PCMCodecTests: XCTestCase {
    func testRoundTripPeaks() {
        let src: [Float] = [0, 0.5, -0.5, 1, -1]
        let data = PCMCodec.int16Data(from: src)
        XCTAssertEqual(data.count, src.count * 2)
        let back = PCMCodec.floats(fromInt16: data)
        XCTAssertEqual(back.count, src.count)
        for i in 0..<src.count {
            XCTAssertEqual(back[i], src[i], accuracy: 0.001)
        }
    }
}

final class SampleRingTests: XCTestCase {
    func testSpillKeepsFullCountAndReconstructs() {
        let ring = SampleRing(sampleRate: 1_000, ramCapSeconds: 2, keepTailSeconds: 1)
        var original: [Float] = []
        for i in 0..<5_000 {
            let v = Float(i % 17) / 17.0
            original.append(v)
        }
        // Append in tap-sized chunks.
        var i = 0
        while i < original.count {
            let end = min(i + 128, original.count)
            ring.append(Array(original[i..<end]))
            i = end
        }
        XCTAssertEqual(ring.count, 5_000)
        // Reads must be correct both while a spill is queued and after it lands.
        XCTAssertEqual(ring.loadRange(start: 0, count: 10).count, 10)
        ring.waitForPendingSpill()
        let tail = ring.snapshotTail(maxSamples: 50)
        XCTAssertEqual(tail.count, 50)

        let mid = ring.loadRange(start: 100, count: 200)
        XCTAssertEqual(mid.count, 200)
        for j in 0..<200 {
            XCTAssertEqual(mid[j], original[100 + j], accuracy: 0.002)
        }

        let delta = ring.copyNew(from: 4_900)
        XCTAssertEqual(delta.count, 100)

        let all = ring.takeAllAndClear()
        XCTAssertEqual(all.count, 5_000)
        XCTAssertEqual(ring.count, 0)
        for j in 0..<5_000 {
            XCTAssertEqual(all[j], original[j], accuracy: 0.002)
        }
    }

    func testCopyNewEmptyWhenCaughtUp() {
        let ring = SampleRing(sampleRate: 16_000, ramCapSeconds: 2, keepTailSeconds: 1)
        ring.append([0.1, 0.2, 0.3])
        XCTAssertTrue(ring.copyNew(from: 3).isEmpty)
        XCTAssertTrue(ring.copyNew(from: 10).isEmpty)
    }
}
