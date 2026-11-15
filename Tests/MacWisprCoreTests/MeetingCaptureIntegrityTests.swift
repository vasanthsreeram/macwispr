import XCTest
@testable import MacWisprCore

/// Records write sizes instead of storing bytes; can fail from the Nth write on.
private final class RecordingSink: PCM16Sink, @unchecked Sendable {
    struct DiskFull: Error {}
    private let failFrom: Int?
    private(set) var writeSizes: [Int] = []
    private(set) var attempts = 0

    init(failFrom: Int? = nil) { self.failFrom = failFrom }

    func write(_ data: Data) throws {
        attempts += 1
        if let failFrom, attempts >= failFrom { throw DiskFull() }
        writeSizes.append(data.count)
    }

    func synchronize() throws {}
    func close() throws {}
}

final class PCM16FileWriterIntegrityTests: XCTestCase {
    private let url = URL(fileURLWithPath: "/dev/null")

    // CR-2 / EDGE-10: a failed write (ENOSPC) must be recorded and must not count as written.
    func testWriteErrorIsRecordedAndSampleCountDoesNotAdvance() {
        let sink = RecordingSink(failFrom: 1)
        let writer = PCM16FileWriter(url: url, sink: sink)
        writer.append([Float](repeating: 0.1, count: 1_600))
        writer.close()
        XCTAssertNotNil(writer.error)
        XCTAssertEqual(writer.sampleCount, 0)
    }

    func testAppendsAfterFirstErrorAreDroppedAndCountStaysAtLastGoodWrite() {
        let sink = RecordingSink(failFrom: 2)
        let writer = PCM16FileWriter(url: url, sink: sink)
        writer.append([Float](repeating: 0.1, count: 1_000))
        writer.append([Float](repeating: 0.1, count: 2_000))
        writer.append([Float](repeating: 0.1, count: 3_000))
        writer.appendSilence(50_000)
        writer.close()
        XCTAssertNotNil(writer.error)
        XCTAssertEqual(writer.sampleCount, 1_000)
        XCTAssertEqual(sink.attempts, 2, "nothing is written after the first failure")
        writer.append([Float](repeating: 0.1, count: 10))
        XCTAssertEqual(writer.sampleCount, 1_000)
    }

    func testHealthyWriterHasNoError() {
        let sink = RecordingSink()
        let writer = PCM16FileWriter(url: url, sink: sink)
        writer.append([Float](repeating: 0.1, count: 500))
        writer.close()
        XCTAssertNil(writer.error)
        XCTAssertEqual(writer.sampleCount, 500)
        XCTAssertEqual(sink.writeSizes, [1_000])
    }

    // CR-1: a multi-hour gap must be written as bounded chunks, never one giant buffer.
    func testMultiHourSilenceIsWrittenInBoundedChunks() {
        let sink = RecordingSink()
        let writer = PCM16FileWriter(url: url, sink: sink)
        let eightHours = 16_000 * 3_600 * 8
        writer.appendSilence(eightHours)
        XCTAssertEqual(writer.sampleCount, eightHours, "queued silence counts toward the timeline")
        writer.close()
        XCTAssertNil(writer.error)
        XCTAssertEqual(writer.sampleCount, eightHours)
        XCTAssertEqual(sink.writeSizes.reduce(0, +), eightHours * 2)
        XCTAssertLessThanOrEqual(sink.writeSizes.max() ?? 0, PCM16FileWriter.silenceChunkSamples * 2)
        XCTAssertGreaterThan(sink.writeSizes.count, 1)
        XCTAssertLessThanOrEqual(PCM16FileWriter.silenceChunkSamples, 16_000 * 60, "chunk stays small")
    }

    func testFileBackedWriterStillWritesPCM() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("pcmw-\(UUID().uuidString).pcm")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let writer = try PCM16FileWriter(url: tmp)
        writer.append([0.5, -0.5])
        writer.appendSilence(3)
        writer.close()
        XCTAssertNil(writer.error)
        let reader = try PCM16FileReader(url: tmp)
        XCTAssertEqual(reader.sampleCount, 5)
    }
}

final class MeetingTimelineTests: XCTestCase {
    // CR-1: the timeline clock must not count time the Mac spent asleep.
    func testClockIsAwakeTimeNotWallClock() {
        let a = MeetingTimeline.awakeNow()
        XCTAssertEqual(a, ProcessInfo.processInfo.systemUptime, accuracy: 0.5)
        XCTAssertEqual(MeetingTimeline.elapsedSamples(since: 100, now: 102.5), 40_000)
        XCTAssertEqual(MeetingTimeline.elapsedSamples(since: 100, now: 99), 0)
    }

    func testSmallJitterIsNotPadded() {
        XCTAssertEqual(MeetingTimeline.silenceToPad(elapsedSamples: 16_000, written: 10_000, incoming: 4_000), 0)
    }

    func testStallIsPaddedToKeepTracksAligned() {
        XCTAssertEqual(MeetingTimeline.silenceToPad(elapsedSamples: 160_000, written: 16_000, incoming: 4_000), 140_000)
    }

    // EDGE-4: an audio drop-out longer than the threshold becomes a warning on the meeting.
    func testStallWarningOnlyAboveThreshold() {
        XCTAssertNil(MeetingTimeline.stallWarning(track: "Microphone", gapSamples: 16_000 * 4, atSample: 0))
        let w = MeetingTimeline.stallWarning(track: "Microphone", gapSamples: 16_000 * 12, atSample: 16_000 * 843)
        XCTAssertNotNil(w)
        XCTAssertTrue(w!.contains("Microphone"))
        XCTAssertTrue(w!.contains("12 s"))
        XCTAssertTrue(w!.contains("14:03"))
    }

    func testTrailingStallWarning() {
        XCTAssertNil(MeetingTimeline.trailingStallWarning(track: "Microphone", elapsedSamples: 16_000 * 60, written: 16_000 * 58))
        let w = MeetingTimeline.trailingStallWarning(track: "Other apps' audio", elapsedSamples: 16_000 * 600, written: 16_000 * 400)
        XCTAssertNotNil(w)
        XCTAssertTrue(w!.contains("3:20"))
    }
}

final class MeetingDiskSpaceTests: XCTestCase {
    private let perTrackHour: Int64 = 16_000 * 2 * 3_600

    func testPlentyOfSpaceIsOK() {
        XCTAssertEqual(MeetingDiskSpace.check(availableBytes: 50_000_000_000, tracks: 2), .ok)
    }

    func testLowSpaceWarns() {
        // One hour of two-track audio fits: enough to start, worth a warning.
        guard case .low(let minutes) = MeetingDiskSpace.check(availableBytes: perTrackHour * 2, tracks: 2) else {
            return XCTFail("expected .low")
        }
        XCTAssertEqual(minutes, 60)
    }

    func testNearlyFullDiskRefuses() {
        guard case .insufficient = MeetingDiskSpace.check(availableBytes: 20_000_000, tracks: 2) else {
            return XCTFail("expected .insufficient")
        }
    }

    func testUnknownSpaceDoesNotBlock() {
        XCTAssertEqual(MeetingDiskSpace.check(availableBytes: nil, tracks: 2), .ok)
    }
}
