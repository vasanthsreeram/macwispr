import AVFoundation
import Darwin
import Foundation
import MacWisprCore
import ParakeetASR

/// ASR gate runner: transcribes every manifest item through one engine using
/// the app's windowing + stitching, and writes a JSON report for check.py.
///
///   swift run -c release ASRGate --engine photon --out bench/results/asr_gate/photon.json
///   swift run -c release ASRGate --engine coreml --model-dir <dir with encoder.mlmodelc …>
///
/// Engines:
///   photon  Python Photon sidecar (current 1.3.0 path), memory = sidecar footprint
///   coreml  speech-swift Core ML Parakeet, in-process, memory = this process footprint

struct Item: Decodable {
    let id: String
    let set: String
    let text: String
    let librispeech: [String]?
    let tts: TTS?
    let silence_seconds: Double?
    struct TTS: Decodable { let voice: String; let file: String }
}

struct Manifest: Decodable { let items: [Item] }

struct ItemResult: Encodable {
    let id: String
    let set: String
    let reference: String
    let hypothesis: String
    let audio_seconds: Double
    let latency_seconds: Double
}

struct Report: Encodable {
    let engine: String
    let model: String
    let host: String
    let date: String
    let load_seconds: Double
    let first_call_seconds: Double
    let idle_footprint_mb: Double
    let peak_footprint_mb: Double
    let items: [ItemResult]
}

protocol Engine {
    var label: String { get }
    func transcribe(_ samples: [Float]) throws -> String
    /// Footprint of whichever process holds the model, plus any memory the
    /// engine holds outside it (Neural Engine wired weights).
    func footprintMB() -> Double
}

/// Wired memory before the engine loaded; set in main.
var wiredBaselineMB: Double = 0

// MARK: - Memory

/// System-wide wired memory. Neural Engine weights are wired by the kernel and
/// do not show in the process footprint, so Core ML runs add this delta.
func wiredMB() -> Double {
    var stats = vm_statistics64()
    var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
    let kr = withUnsafeMutablePointer(to: &stats) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
        }
    }
    guard kr == KERN_SUCCESS else { return 0 }
    return Double(stats.wire_count) * Double(vm_kernel_page_size) / 1_048_576
}

/// `phys_footprint` of a pid, same number Activity Monitor and `footprint` show.
func physFootprintMB(pid: pid_t) -> Double {
    var info = rusage_info_v4()
    let rc = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
            proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
        }
    }
    guard rc == 0 else { return -1 }
    return Double(info.ri_phys_footprint) / 1_048_576
}

// MARK: - Core ML (in-process)

final class CoreMLEngine: Engine {
    let model: ParakeetASRModel
    let label: String

    init(modelDir: String?) async throws {
        if let modelDir {
            // speech-swift resolves `<QWEN3_CACHE_DIR>/qwen3-speech/<org>_<name>` and skips
            // download when that folder has *.safetensors. Point it at a symlink farm.
            let id = "local/asr-gate-model"
            let base = FileManager.default.temporaryDirectory.appendingPathComponent("asr-gate-cache")
            let dir = base.appendingPathComponent("qwen3-speech/local_asr-gate-model")
            try? FileManager.default.removeItem(at: base)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            for name in try FileManager.default.contentsOfDirectory(atPath: modelDir) {
                try FileManager.default.createSymbolicLink(
                    at: dir.appendingPathComponent(name),
                    withDestinationURL: URL(fileURLWithPath: modelDir).appendingPathComponent(name))
            }
            FileManager.default.createFile(atPath: dir.appendingPathComponent("marker.safetensors").path, contents: Data())
            setenv("QWEN3_CACHE_DIR", base.path, 1)
            model = try await ParakeetASRModel.fromPretrained(modelId: id)
            label = "coreml:\(URL(fileURLWithPath: modelDir).lastPathComponent)"
        } else {
            model = try await ParakeetASRModel.fromPretrained(modelId: ParakeetASRModel.int8ModelId)
            label = "coreml:\(ParakeetASRModel.int8ModelId)"
        }
    }

    func transcribe(_ samples: [Float]) throws -> String {
        // Core ML hands back autoreleased IOSurface buffers; drain per call.
        try autoreleasepool {
            try model.transcribeAudio(Self.pad(samples), sampleRate: 16_000)
        }
    }

    /// Same as TranscriptionEngine.prepareParakeetSamples: the fixed-shape
    /// encoder needs mel frames in (2000, 3000].
    static func pad(_ samples: [Float]) -> [Float] {
        let hop = 160
        let minSamples = (2001 - 1) * hop
        let maxSamples = (3000 - 1) * hop
        if samples.count < minSamples {
            return samples + [Float](repeating: 0, count: minSamples - samples.count)
        }
        if samples.count > maxSamples { return Array(samples.suffix(maxSamples)) }
        return samples
    }

    func footprintMB() -> Double {
        physFootprintMB(pid: getpid()) + max(0, wiredMB() - wiredBaselineMB)
    }
}

// MARK: - Photon (Python sidecar)

final class PhotonEngine: Engine {
    let process = Process()
    let stdin: FileHandle
    let stdout: FileHandle
    var buffer = Data()
    let label = "photon:moondream/parakeet-redux"

    init(device: String) throws {
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/MacWispr/photon")
        let python = root.appendingPathComponent("venv/bin/python")
        guard FileManager.default.isExecutableFile(atPath: python.path) else {
            throw NSError(domain: "ASRGate", code: 1, userInfo: [NSLocalizedDescriptionKey:
                "Photon runtime not installed at \(python.path). Launch MacWispr 1.3.0 once."])
        }
        let script = FileManager.default.temporaryDirectory.appendingPathComponent("asr-gate-photon.py")
        try """
        import sys, json, os, warnings
        warnings.filterwarnings("ignore")
        import moondream as md
        speech = md.photon("moondream/parakeet-redux", device="\(device)")
        print(json.dumps({"ready": True}), flush=True)
        for line in sys.stdin:
            req = json.loads(line)
            try:
                print(json.dumps({"text": speech.transcribe(audio=req["wav"]).get("text", "")}), flush=True)
            except Exception as e:
                print(json.dumps({"error": str(e)}), flush=True)
        """.write(to: script, atomically: true, encoding: .utf8)
        process.executableURL = python
        process.arguments = ["-u", script.path]
        var env = ProcessInfo.processInfo.environment
        env["HF_HUB_OFFLINE"] = "1"
        process.environment = env
        let inPipe = Pipe(), outPipe = Pipe()
        process.standardInput = inPipe
        process.standardOutput = outPipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        stdin = inPipe.fileHandleForWriting
        stdout = outPipe.fileHandleForReading
        guard let ready = try readLine(), ready["ready"] as? Bool == true else {
            throw NSError(domain: "ASRGate", code: 2, userInfo: [NSLocalizedDescriptionKey: "Photon failed to load"])
        }
    }

    deinit { process.terminate() }

    func transcribe(_ samples: [Float]) throws -> String {
        let wav = FileManager.default.temporaryDirectory.appendingPathComponent("asr-gate-\(UUID().uuidString).wav")
        try writeWAV(samples, to: wav)
        defer { try? FileManager.default.removeItem(at: wav) }
        stdin.write(try JSONSerialization.data(withJSONObject: ["wav": wav.path]) + Data("\n".utf8))
        guard let resp = try readLine() else { throw NSError(domain: "ASRGate", code: 3) }
        if let err = resp["error"] as? String {
            throw NSError(domain: "ASRGate", code: 4, userInfo: [NSLocalizedDescriptionKey: err])
        }
        return resp["text"] as? String ?? ""
    }

    func footprintMB() -> Double { physFootprintMB(pid: process.processIdentifier) }

    private func readLine() throws -> [String: Any]? {
        while true {
            if let nl = buffer.firstIndex(of: 0x0A) {
                let line = buffer.subdata(in: buffer.startIndex..<nl)
                buffer.removeSubrange(buffer.startIndex...nl)
                if let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any] { return obj }
                continue
            }
            let chunk = stdout.availableData
            if chunk.isEmpty { return nil }
            buffer.append(chunk)
        }
    }
}

func writeWAV(_ samples: [Float], to url: URL) throws {
    let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
    let file = try AVAudioFile(forWriting: url, settings: [
        AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16_000, AVNumberOfChannelsKey: 1,
        AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false,
    ])
    let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(max(samples.count, 1)))!
    buf.frameLength = AVAudioFrameCount(samples.count)
    samples.withUnsafeBufferPointer { buf.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
    try file.write(from: buf)
}

// MARK: - Audio

let root = FileManager.default.currentDirectoryPath
let libri = "\(root)/bench/data/librispeech/LibriSpeech/test-clean"

func loadAudio(_ url: URL) throws -> [Float] {
    let file = try AVAudioFile(forReading: url)
    let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
    let src = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
    try file.read(into: src)
    if file.processingFormat.sampleRate == 16_000, file.processingFormat.channelCount == 1 {
        return Array(UnsafeBufferPointer(start: src.floatChannelData![0], count: Int(src.frameLength)))
    }
    let conv = AVAudioConverter(from: file.processingFormat, to: target)!
    let cap = AVAudioFrameCount(Double(src.frameLength) * 16_000 / file.processingFormat.sampleRate) + 1024
    let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: cap)!
    var done = false
    var err: NSError?
    conv.convert(to: out, error: &err) { _, status in
        if done { status.pointee = .endOfStream; return nil }
        done = true; status.pointee = .haveData; return src
    }
    if let err { throw err }
    return Array(UnsafeBufferPointer(start: out.floatChannelData![0], count: Int(out.frameLength)))
}

func samples(for item: Item) throws -> [Float] {
    if let utts = item.librispeech {
        var all: [Float] = []
        for utt in utts {
            let p = utt.split(separator: "-")
            all += try loadAudio(URL(fileURLWithPath: "\(libri)/\(p[0])/\(p[1])/\(utt).flac"))
            all += [Float](repeating: 0, count: 4_800) // 0.3 s gap between joined utterances
        }
        return all
    }
    if let tts = item.tts {
        return try loadAudio(URL(fileURLWithPath: "\(root)/bench/data/asr_gate/tts/\(tts.file)"))
    }
    return [Float](repeating: 0, count: Int((item.silence_seconds ?? 1) * 16_000))
}

/// Same windowing + stitching as TranscriptionEngine for Parakeet.
func transcribeLong(_ engine: Engine, _ audio: [Float]) throws -> String {
    let windows = AudioChunkPlanner.windows(
        sampleCount: audio.count,
        windowSamples: AudioChunkPlanner.parakeetWindowSamples,
        overlapSamples: AudioChunkPlanner.parakeetOverlapSamples)
    var parts: [String] = []
    for w in windows {
        parts.append(try engine.transcribe(Array(audio[w.startSample..<w.endSample])))
    }
    return TranscriptStitch.join(parts)
}

// MARK: - Main

func arg(_ name: String) -> String? {
    let a = CommandLine.arguments
    guard let i = a.firstIndex(of: name), i + 1 < a.count else { return nil }
    return a[i + 1]
}

let engineName = arg("--engine") ?? "coreml"
let outPath = arg("--out") ?? "bench/results/asr_gate/\(engineName).json"
let limit = arg("--limit").flatMap(Int.init)

do {
    let manifest = try JSONDecoder().decode(
        Manifest.self, from: Data(contentsOf: URL(fileURLWithPath: "\(root)/bench/asr_gate/manifest.json")))
    var items = manifest.items
    if let limit { items = Array(items.prefix(limit)) }

    wiredBaselineMB = wiredMB()
    let t0 = CFAbsoluteTimeGetCurrent()
    let engine: Engine
    switch engineName {
    case "photon": engine = try PhotonEngine(device: arg("--device") ?? "mps")
    case "coreml": engine = try await CoreMLEngine(modelDir: arg("--model-dir"))
    default: fatalError("unknown --engine \(engineName)")
    }
    let load = CFAbsoluteTimeGetCurrent() - t0

    // First call pays graph compilation; the app warms up the same way.
    let t1 = CFAbsoluteTimeGetCurrent()
    _ = try engine.transcribe([Float](repeating: 0, count: 16_000))
    let firstCall = CFAbsoluteTimeGetCurrent() - t1
    let idle = engine.footprintMB()
    var peak = idle

    print("engine \(engine.label)  load \(String(format: "%.1f", load))s  first call \(String(format: "%.2f", firstCall))s  idle \(Int(idle)) MB")

    var results: [ItemResult] = []
    for (n, item) in items.enumerated() {
        let audio = try samples(for: item)
        let ts = CFAbsoluteTimeGetCurrent()
        let text = try transcribeLong(engine, audio)
        let dt = CFAbsoluteTimeGetCurrent() - ts
        peak = max(peak, engine.footprintMB())
        results.append(ItemResult(
            id: item.id, set: item.set, reference: item.text, hypothesis: text,
            audio_seconds: Double(audio.count) / 16_000, latency_seconds: dt))
        if (n + 1) % 20 == 0 || n + 1 == items.count {
            print("  \(n + 1)/\(items.count)  peak \(Int(peak)) MB")
        }
    }

    let report = Report(
        engine: engineName, model: engine.label, host: ProcessInfo.processInfo.hostName,
        date: ISO8601DateFormatter().string(from: Date()),
        load_seconds: load, first_call_seconds: firstCall,
        idle_footprint_mb: idle, peak_footprint_mb: peak, items: results)
    let enc = JSONEncoder()
    enc.outputFormatting = [.prettyPrinted, .sortedKeys]
    let url = URL(fileURLWithPath: outPath)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try enc.encode(report).write(to: url)
    print("wrote \(outPath)")
} catch {
    fputs("ASRGate failed: \(error)\n", stderr)
    exit(1)
}
