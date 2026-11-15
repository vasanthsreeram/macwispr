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

/// Where `PCM16FileWriter` puts its bytes. A file handle in the app; injectable for tests.
public protocol PCM16Sink: AnyObject {
    func write(_ data: Data) throws
    func synchronize() throws
    func close() throws
}

private final class FileHandleSink: PCM16Sink {
    private let handle: FileHandle
    init(_ handle: FileHandle) { self.handle = handle }
    func write(_ data: Data) throws { try handle.write(contentsOf: data) }
    func synchronize() throws { try handle.synchronize() }
    func close() throws { try handle.close() }
}

/// Appends 16-bit PCM to a file. Thread-safe; writes happen on a private serial queue.
/// The first write error (e.g. disk full) is kept in `error`; after it nothing more is written.
public final class PCM16FileWriter: @unchecked Sendable {
    /// Silence is written in pieces this size, so a long gap never needs one huge buffer.
    public static let silenceChunkSamples = 16_000 * 10

    public let url: URL
    private let sink: PCM16Sink
    private let queue: DispatchQueue
    private let lock = NSLock()
    private var written = 0
    private var queued = 0
    private var closed = false
    private var firstError: Error?

    public convenience init(url: URL) throws {
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        self.init(url: url, sink: FileHandleSink(handle))
    }

    public init(url: URL, sink: PCM16Sink) {
        self.url = url
        self.sink = sink
        queue = DispatchQueue(label: "macwispr.pcmwriter.\(url.lastPathComponent)", qos: .utility)
    }

    /// Samples on disk plus ones still queued for disk. Failed writes are not counted.
    public var sampleCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return written + queued
    }

    /// First write error, if any. Once set, the file stops growing.
    public var error: Error? {
        lock.lock()
        defer { lock.unlock() }
        return firstError
    }

    public func append(_ samples: [Float]) {
        guard !samples.isEmpty, reserve(samples.count) else { return }
        let data = PCMCodec.int16Data(from: samples)
        queue.async { self.commit(data, count: samples.count) }
    }

    public func appendSilence(_ count: Int) {
        guard count > 0, reserve(count) else { return }
        queue.async {
            let chunk = Data(count: min(count, Self.silenceChunkSamples) * 2)
            var remaining = count
            while remaining > 0 {
                let n = min(remaining, Self.silenceChunkSamples)
                remaining -= n
                guard self.commit(chunk.prefix(n * 2), count: n) else {
                    self.release(remaining)
                    return
                }
            }
        }
    }

    /// Flushes queued writes and closes the file.
    public func close() {
        lock.lock()
        closed = true
        lock.unlock()
        queue.sync {
            do { try sink.synchronize() } catch { record(error) }
            try? sink.close()
        }
    }

    private func reserve(_ count: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !closed, firstError == nil else { return false }
        queued += count
        return true
    }

    private func release(_ count: Int) {
        lock.lock()
        queued -= count
        lock.unlock()
    }

    /// Writes on the queue; counts the samples only if the write succeeded.
    @discardableResult
    private func commit(_ data: Data, count: Int) -> Bool {
        guard error == nil else { release(count); return false }
        do {
            try sink.write(data)
        } catch {
            record(error)
            release(count)
            return false
        }
        lock.lock()
        queued -= count
        written += count
        lock.unlock()
        return true
    }

    private func record(_ error: Error) {
        lock.lock()
        if firstError == nil { firstError = error }
        lock.unlock()
    }
}
