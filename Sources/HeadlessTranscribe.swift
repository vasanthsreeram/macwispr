import Foundation
import AVFoundation
import Darwin

/// `MacWispr --transcribe-file <audio> [...]` — load the shipped model through
/// the same `TranscriptionEngine` the app uses, transcribe each file, print
/// one JSON line per file, and exit. Used for release checks and benchmarks.
enum HeadlessTranscribe {
    static let flag = "--transcribe-file"

    static var requestedFiles: [String]? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: flag) else { return nil }
        let files = Array(args[(i + 1)...]).filter { !$0.hasPrefix("--") }
        return files.isEmpty ? nil : files
    }

    @MainActor
    static func run(files: [String], state: AppState) {
        Task { @MainActor in
            let engine = state.transcriptionEngine
            let size = state.asrModelSize
            let start = Date()
            do {
                try await engine.loadModel(size: size) { progress, status in
                    FileHandle.standardError.write(Data("setup \(Int(progress * 100))% \(status)\n".utf8))
                }
            } catch {
                emit(["event": "load_failed", "error": error.localizedDescription])
                exit(2)
            }
            var loaded: [String: Any] = [
                "event": "loaded",
                "model": size.rawValue,
                "runtime": await engine.runtimeIdentifier ?? "unknown",
                "seconds": Date().timeIntervalSince(start),
            ]
            await addMemory(to: &loaded, engine: engine)
            emit(loaded)
            var failed = false
            for path in files {
                do {
                    let samples = try loadMono16k(path)
                    let t = Date()
                    let text = try await engine.transcribe(samples: samples)
                    var result: [String: Any] = ["file": path, "text": text, "seconds": Date().timeIntervalSince(t),
                                                "runtime": await engine.runtimeIdentifier ?? "unknown"]
                    await addMemory(to: &result, engine: engine)
                    emit(result)
                } catch {
                    failed = true
                    emit(["file": path, "error": error.localizedDescription])
                }
            }
            exit(failed ? 1 : 0)
        }
    }

    private static func addMemory(to output: inout [String: Any], engine: TranscriptionEngine) async {
        var usage = rusage()
        if getrusage(RUSAGE_SELF, &usage) == 0 {
            output["app_peak_rss_bytes"] = usage.ru_maxrss
        }
        do {
            if let stats = try await engine.reduxDiagnostics() {
                let data = try JSONEncoder().encode(stats)
                output["backend_memory"] = try JSONSerialization.jsonObject(with: data)
            }
        } catch {
            output["memory_error"] = error.localizedDescription
        }
    }

    private static func emit(_ obj: [String: Any]) {
        if let data = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]) {
            FileHandle.standardOutput.write(data + Data("\n".utf8))
        }
    }

    /// Decode any CoreAudio-readable file to 16 kHz mono Float32.
    static func loadMono16k(_ path: String) throws -> [Float] {
        let file = try AVAudioFile(forReading: URL(fileURLWithPath: path))
        let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
        guard let converter = AVAudioConverter(from: file.processingFormat, to: target) else {
            throw NSError(domain: "MacWispr", code: 1, userInfo: [NSLocalizedDescriptionKey: "unsupported audio format"])
        }
        let inBuf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: inBuf)
        let ratio = 16_000 / file.processingFormat.sampleRate
        let outBuf = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: AVAudioFrameCount(Double(file.length) * ratio) + 1024)!
        var consumed = false
        var err: NSError?
        converter.convert(to: outBuf, error: &err) { _, status in
            if consumed { status.pointee = .endOfStream; return nil }
            consumed = true
            status.pointee = .haveData
            return inBuf
        }
        if let err { throw err }
        let ptr = outBuf.floatChannelData![0]
        return Array(UnsafeBufferPointer(start: ptr, count: Int(outBuf.frameLength)))
    }
}
