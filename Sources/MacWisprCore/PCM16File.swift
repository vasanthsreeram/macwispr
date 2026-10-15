import Foundation

/// Random access to a headerless 16-bit little-endian mono PCM file.
public final class PCM16FileReader: @unchecked Sendable {
    public let url: URL
    public let sampleCount: Int
    private let handle: FileHandle
    private let lock = NSLock()

    public init(url: URL) throws {
        self.url = url
        handle = try FileHandle(forReadingFrom: url)
        let bytes = try handle.seekToEnd()
        sampleCount = Int(bytes) / 2
    }

    deinit {
        try? handle.close()
    }

    public func read(start: Int, count: Int) -> [Float] {
        let from = max(0, start)
        let n = min(count, sampleCount - from)
        guard n > 0 else { return [] }
        lock.lock()
        defer { lock.unlock() }
        guard (try? handle.seek(toOffset: UInt64(from * 2))) != nil,
              let data = try? handle.read(upToCount: n * 2)
        else { return [] }
        return PCMCodec.floats(fromInt16: data)
    }
}

/// Appends 16-bit PCM to a file. Thread-safe; writes happen on a private serial queue.
public final class PCM16FileWriter: @unchecked Sendable {
    public let url: URL
    private let handle: FileHandle
    private let queue: DispatchQueue
    private let lock = NSLock()
    private var written = 0
    private var closed = false

    public init(url: URL) throws {
        self.url = url
        FileManager.default.createFile(atPath: url.path, contents: nil)
        handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        queue = DispatchQueue(label: "macwispr.pcmwriter.\(url.lastPathComponent)", qos: .utility)
    }

    /// Samples accepted so far (including ones still queued for disk).
    public var sampleCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return written
    }

    public func append(_ samples: [Float]) {
        guard !samples.isEmpty else { return }
        lock.lock()
        guard !closed else { lock.unlock(); return }
        written += samples.count
        lock.unlock()
        let data = PCMCodec.int16Data(from: samples)
        queue.async { [handle] in try? handle.write(contentsOf: data) }
    }

    public func appendSilence(_ count: Int) {
        guard count > 0 else { return }
        append([Float](repeating: 0, count: count))
    }

    /// Flushes queued writes and closes the file.
    public func close() {
        lock.lock()
        closed = true
        lock.unlock()
        queue.sync {
            try? handle.synchronize()
            try? handle.close()
        }
    }
}
