import Foundation

/// 16 kHz capture buffer that keeps only a short RAM tail and spills older
/// samples to a PCM16 temp file so hour-long dictation does not grow RSS.
public final class SampleRing: @unchecked Sendable {
    public let sampleRate: Int
    public let ramCapSamples: Int
    public let keepTailSamples: Int

    private let lock = NSLock()
    private var ram: [Float] = []
    /// Absolute index of `ram[0]` in the session (samples already spilled).
    private var ramStart = 0
    private var spilledURL: URL?
    private var spilledHandle: FileHandle?
    private var spilledCount = 0
    private var totalCount = 0
    /// Bumped by `reset()` so an in-flight spill never trims a new session.
    private var generation = 0
    private var spillScheduled = false
    /// Disk spill runs here; `append` is called from the real-time audio tap.
    private let spillQueue = DispatchQueue(label: "macwispr.samplering.spill", qos: .utility)

    public init(
        sampleRate: Int = AudioChunkPlanner.sampleRate,
        ramCapSeconds: Int = MemoryPressurePolicy.ramCapSeconds,
        keepTailSeconds: Int = MemoryPressurePolicy.ramLiveWindowSeconds
    ) {
        self.sampleRate = sampleRate
        self.ramCapSamples = max(sampleRate, ramCapSeconds * sampleRate)
        self.keepTailSamples = min(
            ramCapSamples,
            max(sampleRate / 4, keepTailSeconds * sampleRate)
        )
        ram.reserveCapacity(min(ramCapSamples, sampleRate * 8))
    }

    deinit {
        closeSpill(delete: true)
    }

    public var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return totalCount
    }

    public var duration: TimeInterval {
        Double(count) / Double(sampleRate)
    }

    public func reset() {
        lock.lock()
        generation += 1
        ram.removeAll(keepingCapacity: true)
        ramStart = 0
        totalCount = 0
        spilledCount = 0
        lock.unlock()
        spillQueue.sync { closeSpill(delete: true) }
    }

    /// Waits for any queued disk spill (tests and diagnostics).
    public func waitForPendingSpill() {
        spillQueue.sync {}
    }

    public func append(_ samples: [Float]) {
        samples.withUnsafeBufferPointer { append($0) }
    }

    public func append(_ samples: UnsafeBufferPointer<Float>) {
        guard !samples.isEmpty else { return }
        lock.lock()
        ram.append(contentsOf: samples)
        totalCount += samples.count
        let shouldSpill = ram.count > ramCapSamples && !spillScheduled
        if shouldSpill { spillScheduled = true }
        lock.unlock()
        if shouldSpill {
            spillQueue.async { [weak self] in self?.spillIfNeeded() }
        }
    }

    /// Copy samples at `absoluteOffset..<count` (for Grok delta send).
    public func copyNew(from absoluteOffset: Int) -> [Float] {
        lock.lock()
        let end = totalCount
        lock.unlock()
        let start = max(0, absoluteOffset)
        guard start < end else { return [] }
        return loadRange(start: start, count: end - start)
    }

    public func snapshotTail(maxSamples: Int) -> [Float] {
        lock.lock()
        let end = totalCount
        lock.unlock()
        let n = min(max(0, maxSamples), end)
        guard n > 0 else { return [] }
        return loadRange(start: end - n, count: n)
    }

    public func loadRange(start: Int, count requested: Int) -> [Float] {
        guard requested > 0 else { return [] }
        lock.lock()
        let end = min(start + requested, totalCount)
        let from = max(0, start)
        guard from < end else {
            lock.unlock()
            return []
        }
        let ramStartCopy = ramStart
        let ramCopy: [Float]
        let needSpill = from < ramStartCopy
        ramCopy = ram
        let spilledURLCopy = spilledURL
        lock.unlock()

        var out = [Float](repeating: 0, count: end - from)
        var i = 0
        var cursor = from
        if needSpill, let url = spilledURLCopy {
            let spillEnd = min(end, ramStartCopy)
            if cursor < spillEnd {
                let spillSamples = Self.readSpill(url: url, start: cursor, count: spillEnd - cursor)
                for s in spillSamples {
                    out[i] = s
                    i += 1
                }
                cursor += spillSamples.count
            }
        }
        while cursor < end {
            let local = cursor - ramStartCopy
            if local >= 0, local < ramCopy.count {
                out[i] = ramCopy[local]
                i += 1
                cursor += 1
            } else {
                break
            }
        }
        if i < out.count {
            out.removeLast(out.count - i)
        }
        return out
    }

    /// Reconstruct the whole capture. Avoid on hour-long clips — prefer `loadRange`.
    public func takeAllAndClear() -> [Float] {
        let all = loadRange(start: 0, count: count)
        reset()
        return all
    }

    /// Transcribe overlapping windows without materializing the full session.
    public func transcribeWindows(
        windowSamples: Int,
        overlapSamples: Int,
        transcribe: ([Float]) async throws -> String
    ) async throws -> String {
        let n = count
        let windows = AudioChunkPlanner.windows(
            sampleCount: n,
            windowSamples: windowSamples,
            overlapSamples: overlapSamples
        )
        var parts: [String] = []
        parts.reserveCapacity(windows.count)
        for w in windows {
            let chunk = loadRange(start: w.startSample, count: w.count)
            let text = try await transcribe(chunk)
            parts.append(text)
        }
        return TranscriptStitch.join(parts)
    }

    /// Runs on `spillQueue`. Writes the oldest samples to disk first, then
    /// drops them from RAM, so readers never see a range that is not on disk yet.
    private func spillIfNeeded() {
        lock.lock()
        spillScheduled = false
        let gen = generation
        let extra = ram.count - keepTailSamples
        guard extra > 0, ram.count > ramCapSamples else {
            lock.unlock()
            return
        }
        let toSpill = Array(ram.prefix(extra))
        lock.unlock()

        do {
            let handle = try spillHandle()
            try handle.write(contentsOf: PCMCodec.int16Data(from: toSpill))
        } catch {
            NSLog("MacWispr SampleRing: spill failed: \(error.localizedDescription)")
            return
        }

        lock.lock()
        if gen == generation, ram.count >= extra {
            ram.removeFirst(extra)
            ramStart += extra
            spilledCount += extra
        }
        lock.unlock()
    }

    private func spillHandle() throws -> FileHandle {
        if let spilledHandle { return spilledHandle }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("macwispr-\(UUID().uuidString).pcm16")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        lock.lock()
        spilledURL = url
        lock.unlock()
        spilledHandle = handle
        return handle
    }

    private func closeSpill(delete: Bool) {
        try? spilledHandle?.close()
        spilledHandle = nil
        lock.lock()
        let url = spilledURL
        spilledURL = nil
        lock.unlock()
        if delete, let url {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private static func readSpill(url: URL, start: Int, count: Int) -> [Float] {
        guard count > 0 else { return [] }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }
        let byteStart = UInt64(start) * 2
        let byteCount = count * 2
        do {
            try handle.seek(toOffset: byteStart)
            guard let data = try handle.read(upToCount: byteCount) else { return [] }
            return PCMCodec.floats(fromInt16: data)
        } catch {
            return []
        }
    }
}
