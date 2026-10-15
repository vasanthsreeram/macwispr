import XCTest
@testable import MacWisprCore

final class MeetingSegmenterTests: XCTestCase {
    private let sr = 16_000

    /// Low noise with loud tone bursts at the given (start, length) seconds.
    private func signal(seconds: Double, bursts: [(Double, Double)]) -> [Float] {
        var s = (0..<Int(seconds * Double(sr))).map { i in Float(sin(Double(i) * 1.7)) * 0.001 }
        for (start, len) in bursts {
            let a = Int(start * Double(sr)), b = min(s.count, Int((start + len) * Double(sr)))
            for i in a..<b { s[i] = Float(sin(Double(i) * 2 * .pi * 220 / Double(sr))) * 0.3 }
        }
        return s
    }

    func testFindsSpeechAndSkipsSilence() {
        let s = signal(seconds: 20, bursts: [(2, 3), (10, 2)])
        let regions = MeetingSegmenter.regions(levels: MeetingSegmenter.frameLevels(s), totalSamples: s.count)
        XCTAssertEqual(regions.count, 2)
        XCTAssertEqual(Double(regions[0].lowerBound) / Double(sr), 1.5, accuracy: 0.1)
        XCTAssertEqual(Double(regions[0].upperBound) / Double(sr), 5.5, accuracy: 0.1)
        XCTAssertEqual(Double(regions[1].lowerBound) / Double(sr), 9.5, accuracy: 0.1)
    }

    func testSilenceGivesNoRegions() {
        let s = [Float](repeating: 0, count: sr * 5)
        XCTAssertTrue(MeetingSegmenter.regions(levels: MeetingSegmenter.frameLevels(s), totalSamples: s.count).isEmpty)
    }

    func testShortPausesMergeIntoOneRegion() {
        let s = signal(seconds: 10, bursts: [(1, 2), (3.3, 2)])
        let regions = MeetingSegmenter.regions(levels: MeetingSegmenter.frameLevels(s), totalSamples: s.count)
        XCTAssertEqual(regions.count, 1)
    }

    func testLongSpeechIsCutBelowMaxLength() {
        let s = signal(seconds: 70, bursts: [(0, 70)])
        let regions = MeetingSegmenter.regions(levels: MeetingSegmenter.frameLevels(s), totalSamples: s.count)
        XCTAssertGreaterThanOrEqual(regions.count, 3)
        for r in regions { XCTAssertLessThanOrEqual(r.count, 24 * sr) }
        // Contiguous, no gaps or overlaps.
        for (a, b) in zip(regions, regions.dropFirst()) { XCTAssertEqual(a.upperBound, b.lowerBound) }
        XCTAssertEqual(regions.first?.lowerBound, 0)
        XCTAssertEqual(regions.last?.upperBound, s.count)
    }
}

final class MeetingMergeTests: XCTestCase {
    func testDropsMicEchoOfSystemAudio() {
        let segs = [
            MeetingSegment(start: 1, end: 4, source: .system, text: "Can everyone see my screen now?"),
            MeetingSegment(start: 1.2, end: 4.1, source: .microphone, text: "everyone see my screen now"),
            MeetingSegment(start: 5, end: 7, source: .microphone, text: "Yes, I can see it."),
        ]
        let merged = MeetingMerge.merge(segs)
        XCTAssertEqual(merged.map(\.text), ["Can everyone see my screen now?", "Yes, I can see it."])
    }

    func testKeepsMicWhenNoSystemAudio() {
        let segs = [MeetingSegment(start: 0, end: 1, source: .microphone, text: "Hello")]
        XCTAssertEqual(MeetingMerge.merge(segs), segs)
    }

    func testSortsByTimeAndDropsEmpty() {
        let segs = [
            MeetingSegment(start: 5, end: 6, source: .system, text: "second"),
            MeetingSegment(start: 1, end: 2, source: .microphone, text: "first"),
            MeetingSegment(start: 3, end: 4, source: .system, text: "  "),
        ]
        XCTAssertEqual(MeetingMerge.merge(segs).map(\.text), ["first", "second"])
    }
}

final class AgentDataStoreTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("mw-agent-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func write<T: Encodable>(_ value: T, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try AgentDataStore.makeEncoder().encode(value).write(to: url)
    }

    func testHistoryFiltersAndSorts() throws {
        let paths = MacWisprPaths(root: root)
        let now = Date()
        try write([
            DictationRecord(text: "old note about budgets", timestamp: now.addingTimeInterval(-10 * 86_400), duration: 2, wordCount: 4),
            DictationRecord(text: "new budget email", timestamp: now.addingTimeInterval(-60), duration: 2, wordCount: 3),
            DictationRecord(text: " ", timestamp: now, duration: 1, wordCount: 0),
        ], to: paths.historyFile)
        let store = AgentDataStore(paths: paths)
        XCTAssertEqual(store.dictations().map(\.text), ["new budget email", "old note about budgets"])
        XCTAssertEqual(store.dictations(since: SinceParser.parse("7d", now: now)).count, 1)
        XCTAssertEqual(store.dictations(query: "BUDGET", limit: 1).first?.text, "new budget email")
    }

    func testMeetingsListLatestAndSearch() throws {
        let paths = MacWisprPaths(root: root)
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        for (i, text) in ["kickoff call", "pricing review"].enumerated() {
            let start = t0.addingTimeInterval(Double(i) * 3600)
            let id = MeetingMetadata.makeID(for: start)
            let dir = paths.meetingDir(id: id)
            try write(MeetingMetadata(id: id, title: "M\(i)", startedAt: start, durationSeconds: 60, status: .done,
                                      recordMicrophone: true, recordSystemAudio: true), to: dir.appendingPathComponent(MeetingFiles.metadata))
            try write(MeetingTranscript(segments: [MeetingSegment(start: 12, end: 15, source: .system, text: text)]),
                      to: dir.appendingPathComponent(MeetingFiles.transcriptJSON))
        }
        let store = AgentDataStore(paths: paths)
        XCTAssertEqual(store.meetings().map(\.title), ["M1", "M0"])
        let latest = try XCTUnwrap(store.resolveMeetingID("latest"))
        XCTAssertEqual(store.meeting(id: latest)?.title, "M1")
        XCTAssertNil(store.resolveMeetingID("../etc"))
        let md = try XCTUnwrap(store.transcriptMarkdown(id: latest))
        XCTAssertTrue(md.contains("[00:00:12] **Others:** pricing review"), md)
        let hits = store.search("pricing")
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits.first?.offsetSeconds, 12)
    }

    func testSinceParser() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(SinceParser.parse("2h", now: now), now.addingTimeInterval(-7200))
        XCTAssertEqual(SinceParser.parse("1w", now: now), now.addingTimeInterval(-604_800))
        XCTAssertNotNil(SinceParser.parse("2026-10-01"))
        XCTAssertNil(SinceParser.parse("soon"))
    }
}
