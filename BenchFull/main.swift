import Foundation
import CoreML
import Qwen3ASR
import ParakeetASR
import AudioCommon

/// Full ASR suite: latency (single clip) + WER (LibriSpeech subset)
/// across Qwen MLX, Qwen CoreML hybrid, Qwen full CoreML, and Parakeet CoreML.
@main
struct BenchFull {
    // MARK: - Config

    static let defaultClip = "bench/clips/speech_12s_16k.wav"
    static let librispeechRoot = "bench/data/librispeech/LibriSpeech/test-clean"
    static let latencyRuns = 3
    static let defaultMaxFiles = 50
    static let minSec: Double = 1.0
    static let maxSec: Double = 30.0

    // MARK: - Types

    enum EngineKind: String {
        case qwenMLX
        case qwenHybrid
        case qwenFullCoreML
        case parakeetCoreML
    }

    struct EngineSpec {
        let id: String
        let label: String
        let kind: EngineKind
        let modelId: String
        /// For hybrid: MLX decoder model id (encoder is CoreML default).
        let decoderModelId: String?
    }

    struct LatencyResult {
        let id: String
        let label: String
        let engine: String
        let best: Double
        let mean: Double
        let rtf: Double
        let load: Double
        let warmup: Double
        let preview: String
        let error: String?
    }

    struct Utterance {
        let id: String
        let path: URL
        let text: String
        let duration: Double
    }

    struct WerResult {
        let id: String
        let label: String
        let engine: String
        let utterances: Int
        let totalAudio: Double
        let totalInfer: Double
        let totalRefWords: Int
        let totalErrors: Int
        let subs: Int
        let ins: Int
        let dels: Int
        let meanWer: Double
        let aggregateWer: Double
        let rtf: Double
        let samples: [(id: String, ref: String, hyp: String, wer: Double)]
        let error: String?
    }

    // MARK: - Catalog (app-relevant + CoreML variants)

    static let engines: [EngineSpec] = [
        EngineSpec(
            id: "qwen-0.6b-mlx-8bit",
            label: "Qwen3 0.6B MLX-8bit (app default)",
            kind: .qwenMLX,
            modelId: "mlx-community/Qwen3-ASR-0.6B-8bit",
            decoderModelId: nil
        ),
        EngineSpec(
            id: "qwen-1.7b-mlx-8bit",
            label: "Qwen3 1.7B MLX-8bit",
            kind: .qwenMLX,
            modelId: "mlx-community/Qwen3-ASR-1.7B-8bit",
            decoderModelId: nil
        ),
        EngineSpec(
            id: "qwen-0.6b-hybrid-coreml",
            label: "Qwen3 0.6B hybrid (CoreML enc + MLX dec)",
            kind: .qwenHybrid,
            modelId: CoreMLASREncoder.defaultModelId,
            decoderModelId: "mlx-community/Qwen3-ASR-0.6B-8bit"
        ),
        // Full CoreML decoder is currently unusable with published weights:
        // HF ships decoder_part1/part2.mlmodelc but speech-swift expects a single
        // decoder.mlmodelc. Kept for discovery; expect a clear load error.
        EngineSpec(
            id: "qwen-0.6b-full-coreml",
            label: "Qwen3 0.6B full CoreML (enc+dec ANE)",
            kind: .qwenFullCoreML,
            modelId: CoreMLASREncoder.defaultModelId,
            decoderModelId: nil
        ),
        EngineSpec(
            id: "parakeet-v3-coreml",
            label: "Parakeet TDT v3 CoreML INT8 (in-app)",
            kind: .parakeetCoreML,
            modelId: ParakeetASRModel.int8ModelId,
            decoderModelId: nil
        ),
    ]

    // MARK: - Runtime engine holders

    final class LoadedEngine {
        let spec: EngineSpec
        var qwen: Qwen3ASRModel?
        var coremlEncoder: CoreMLASREncoder?
        var fullCoreML: AnyObject? // CoreMLASRModel when available
        var parakeet: ParakeetASRModel?
        var loadSeconds: Double = 0
        var warmupSeconds: Double = 0

        init(spec: EngineSpec) { self.spec = spec }

        func unload() {
            qwen?.unload()
            qwen = nil
            coremlEncoder = nil
            fullCoreML = nil
            parakeet?.unload()
            parakeet = nil
        }

        func transcribe(_ samples: [Float], duration: Double) throws -> String {
            let maxTokens = min(256, max(64, Int(duration * 25)))
            switch spec.kind {
            case .qwenMLX:
                guard let model = qwen else { throw BenchError.notLoaded }
                return model.transcribe(
                    audio: samples, sampleRate: 16000, maxTokens: maxTokens)
            case .qwenHybrid:
                guard let model = qwen, let enc = coremlEncoder else {
                    throw BenchError.notLoaded
                }
                return try model.transcribe(
                    audio: samples, sampleRate: 16000, maxTokens: maxTokens,
                    coremlEncoder: enc)
            case .qwenFullCoreML:
                if #available(macOS 15, *) {
                    guard let model = fullCoreML as? CoreMLASRModel else {
                        throw BenchError.notLoaded
                    }
                    return try model.transcribe(
                        audio: samples, sampleRate: 16000, maxTokens: maxTokens)
                }
                throw BenchError.unsupportedOS("full CoreML needs macOS 15+")
            case .parakeetCoreML:
                guard let model = parakeet else { throw BenchError.notLoaded }
                return try model.transcribeAudio(
                    prepareParakeetSamples(samples), sampleRate: 16000)
            }
        }
    }

    enum BenchError: LocalizedError {
        case notLoaded
        case unsupportedOS(String)
        case noLibriSpeech
        case audioLoad(String)

        var errorDescription: String? {
            switch self {
            case .notLoaded: return "Model not loaded"
            case .unsupportedOS(let s): return s
            case .noLibriSpeech: return "LibriSpeech not found at \(librispeechRoot)"
            case .audioLoad(let s): return "Audio load failed: \(s)"
            }
        }
    }

    // MARK: - Parakeet pad (match app)

    static func prepareParakeetSamples(_ samples: [Float]) -> [Float] {
        let hop = 160
        let minSamples = (2001 - 1) * hop
        let maxSamples = (3000 - 1) * hop
        if samples.count < minSamples {
            var padded = samples
            padded.append(contentsOf: repeatElement(Float(0), count: minSamples - samples.count))
            return padded
        }
        if samples.count > maxSamples {
            return Array(samples.suffix(maxSamples))
        }
        return samples
    }

    // MARK: - Load

    static func loadEngine(_ spec: EngineSpec) async throws -> LoadedEngine {
        let loaded = LoadedEngine(spec: spec)
        let t0 = CFAbsoluteTimeGetCurrent()
        let silence = [Float](repeating: 0, count: 16_000)

        switch spec.kind {
        case .qwenMLX:
            let model = try await Qwen3ASRModel.fromPretrained(modelId: spec.modelId)
            loaded.qwen = model
            loaded.loadSeconds = CFAbsoluteTimeGetCurrent() - t0
            let w0 = CFAbsoluteTimeGetCurrent()
            _ = model.transcribe(audio: silence, sampleRate: 16000, maxTokens: 8)
            loaded.warmupSeconds = CFAbsoluteTimeGetCurrent() - w0

        case .qwenHybrid:
            let enc = try await CoreMLASREncoder.fromPretrained(
                computeUnits: .cpuAndNeuralEngine)
            try enc.warmUp()
            let decoderId = spec.decoderModelId ?? "mlx-community/Qwen3-ASR-0.6B-8bit"
            let model = try await Qwen3ASRModel.fromPretrained(modelId: decoderId)
            loaded.coremlEncoder = enc
            loaded.qwen = model
            loaded.loadSeconds = CFAbsoluteTimeGetCurrent() - t0
            let w0 = CFAbsoluteTimeGetCurrent()
            _ = try model.transcribe(
                audio: silence, sampleRate: 16000, maxTokens: 8, coremlEncoder: enc)
            loaded.warmupSeconds = CFAbsoluteTimeGetCurrent() - w0

        case .qwenFullCoreML:
            if #available(macOS 15, *) {
                let model = try await CoreMLASRModel.fromPretrained(
                    computeUnits: .cpuAndNeuralEngine)
                loaded.fullCoreML = model
                loaded.loadSeconds = CFAbsoluteTimeGetCurrent() - t0
                let w0 = CFAbsoluteTimeGetCurrent()
                try model.warmUp()
                loaded.warmupSeconds = CFAbsoluteTimeGetCurrent() - w0
            } else {
                throw BenchError.unsupportedOS("macOS 15+ required for full CoreML")
            }

        case .parakeetCoreML:
            let model = try await ParakeetASRModel.fromPretrained(modelId: spec.modelId)
            loaded.parakeet = model
            loaded.loadSeconds = CFAbsoluteTimeGetCurrent() - t0
            let w0 = CFAbsoluteTimeGetCurrent()
            _ = try model.transcribeAudio(
                prepareParakeetSamples(silence), sampleRate: 16_000)
            loaded.warmupSeconds = CFAbsoluteTimeGetCurrent() - w0
        }

        return loaded
    }

    // MARK: - Latency

    static func runLatency(engine: LoadedEngine, audio: [Float], duration: Double) -> LatencyResult {
        var times: [Double] = []
        var lastText = ""
        var err: String?
        do {
            for _ in 1...latencyRuns {
                let t0 = CFAbsoluteTimeGetCurrent()
                lastText = try engine.transcribe(audio, duration: duration)
                times.append(CFAbsoluteTimeGetCurrent() - t0)
            }
        } catch {
            err = error.localizedDescription
        }
        let best = times.min() ?? .infinity
        let mean = times.isEmpty ? .infinity : times.reduce(0, +) / Double(times.count)
        return LatencyResult(
            id: engine.spec.id,
            label: engine.spec.label,
            engine: engine.spec.kind.rawValue,
            best: best,
            mean: mean,
            rtf: best.isFinite ? best / duration : .infinity,
            load: engine.loadSeconds,
            warmup: engine.warmupSeconds,
            preview: preview(lastText),
            error: err
        )
    }

    // MARK: - LibriSpeech + WER

    static func loadUtterances(maxFiles: Int) throws -> [Utterance] {
        let root = URL(fileURLWithPath: librispeechRoot)
        guard FileManager.default.fileExists(atPath: root.path) else {
            throw BenchError.noLibriSpeech
        }

        var all: [(id: String, path: URL, text: String)] = []
        let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        while let url = enumerator?.nextObject() as? URL {
            guard url.lastPathComponent.hasSuffix(".trans.txt") else { continue }
            let chapterDir = url.deletingLastPathComponent()
            let content = try String(contentsOf: url, encoding: .utf8)
            for line in content.split(separator: "\n", omittingEmptySubsequences: true) {
                let parts = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
                guard parts.count == 2 else { continue }
                let uttId = String(parts[0])
                let text = String(parts[1])
                let flac = chapterDir.appendingPathComponent("\(uttId).flac")
                if FileManager.default.fileExists(atPath: flac.path) {
                    all.append((uttId, flac, text))
                }
            }
        }
        all.sort { $0.id < $1.id }

        var selected: [Utterance] = []
        for item in all {
            do {
                let samples = try AudioFileLoader.load(url: item.path, targetSampleRate: 16000)
                let dur = Double(samples.count) / 16000.0
                guard dur >= minSec, dur <= maxSec else { continue }
                selected.append(Utterance(
                    id: item.id, path: item.path, text: item.text, duration: dur))
                if maxFiles > 0, selected.count >= maxFiles { break }
            } catch {
                continue
            }
        }
        return selected
    }

    static func normalize(_ text: String) -> [String] {
        var t = text.lowercased()
        t = t.replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "‘", with: "'")
            .replacingOccurrences(of: "`", with: "'")
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "' "))
        t = String(t.unicodeScalars.map { allowed.contains($0) ? Character($0) : " " })
        return t.split(whereSeparator: \.isWhitespace)
            .map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: "'")) }
            .filter { !$0.isEmpty }
    }

    /// Levenshtein with S/I/D counts.
    static func editCounts(ref: [String], hyp: [String]) -> (s: Int, i: Int, d: Int, total: Int) {
        let n = ref.count, m = hyp.count
        var dp = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in 0...n { dp[i][0] = i }
        for j in 0...m { dp[0][j] = j }
        if n > 0 && m > 0 {
            for i in 1...n {
                for j in 1...m {
                    if ref[i - 1] == hyp[j - 1] {
                        dp[i][j] = dp[i - 1][j - 1]
                    } else {
                        dp[i][j] = 1 + min(dp[i - 1][j], dp[i][j - 1], dp[i - 1][j - 1])
                    }
                }
            }
        }
        var s = 0, ins = 0, d = 0
        var i = n, j = m
        while i > 0 || j > 0 {
            if i > 0, j > 0, ref[i - 1] == hyp[j - 1] {
                i -= 1; j -= 1
            } else if i > 0, j > 0, dp[i][j] == dp[i - 1][j - 1] + 1 {
                s += 1; i -= 1; j -= 1
            } else if j > 0, dp[i][j] == dp[i][j - 1] + 1 {
                ins += 1; j -= 1
            } else {
                d += 1; i -= 1
            }
        }
        return (s, ins, d, s + ins + d)
    }

    static func runWER(engine: LoadedEngine, utts: [Utterance]) -> WerResult {
        var totalErr = 0, totalRef = 0
        var subs = 0, ins = 0, dels = 0
        var perWer: [Double] = []
        var totalInfer = 0.0
        var totalAudio = 0.0
        var samples: [(id: String, ref: String, hyp: String, wer: Double)] = []
        var runError: String?

        for (idx, u) in utts.enumerated() {
            do {
                let audio = try AudioFileLoader.load(url: u.path, targetSampleRate: 16000)
                let t0 = CFAbsoluteTimeGetCurrent()
                let hyp = try engine.transcribe(audio, duration: u.duration)
                let elapsed = CFAbsoluteTimeGetCurrent() - t0
                totalInfer += elapsed
                totalAudio += u.duration

                let refW = normalize(u.text)
                let hypW = normalize(hyp)
                let counts = editCounts(ref: refW, hyp: hypW)
                let n = max(refW.count, 1)
                let wer = Double(counts.total) / Double(n) * 100.0
                perWer.append(wer)
                totalErr += counts.total
                totalRef += refW.count
                subs += counts.s
                ins += counts.i
                dels += counts.d

                if samples.count < 5 || wer > 15 {
                    if samples.count < 8 {
                        samples.append((u.id, u.text, hyp, wer))
                    }
                }

                if (idx + 1) % 10 == 0 || idx == 0 {
                    let soFar = totalRef > 0 ? Double(totalErr) / Double(totalRef) * 100 : 0
                    print(String(
                        format: "    [%2d/%2d] %.2fs audio  infer %.2fs  WER so far %.2f%%",
                        idx + 1, utts.count, totalAudio, totalInfer, soFar))
                }
            } catch {
                runError = error.localizedDescription
                print("    ✗ \(u.id): \(error.localizedDescription)")
            }
        }

        let agg = totalRef > 0 ? Double(totalErr) / Double(totalRef) * 100 : 100
        let mean = perWer.isEmpty ? 100 : perWer.reduce(0, +) / Double(perWer.count)
        let rtf = totalAudio > 0 ? totalInfer / totalAudio : .infinity

        return WerResult(
            id: engine.spec.id,
            label: engine.spec.label,
            engine: engine.spec.kind.rawValue,
            utterances: perWer.count,
            totalAudio: totalAudio,
            totalInfer: totalInfer,
            totalRefWords: totalRef,
            totalErrors: totalErr,
            subs: subs,
            ins: ins,
            dels: dels,
            meanWer: mean,
            aggregateWer: agg,
            rtf: rtf,
            samples: samples,
            error: runError
        )
    }

    // MARK: - Main

    static func main() async {
        let args = Array(CommandLine.arguments.dropFirst())
        let maxFiles = parseIntFlag(args, name: "--max-files") ?? defaultMaxFiles
        let latencyOnly = args.contains("--latency-only")
        let werOnly = args.contains("--wer-only")
        let onlyIds = parseOnly(args)
        let clip = args.first(where: { !$0.hasPrefix("--") && !$0.hasPrefix("bench/") && $0.hasSuffix(".wav") })
            ?? args.first(where: { $0.hasSuffix(".wav") })
            ?? defaultClip

        let host = ProcessInfo.processInfo.hostName
        let memGB = ProcessInfo.processInfo.physicalMemory / 1_073_741_824

        print("╔══════════════════════════════════════════════════════════════════╗")
        print("║   BenchFull — Latency + WER (Qwen MLX / CoreML + Parakeet)       ║")
        print("╚══════════════════════════════════════════════════════════════════╝")
        print("Host: \(host)  RAM: \(memGB) GB  OS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        print("Clip: \(clip)")
        print("WER: LibriSpeech test-clean, max \(maxFiles) utts (\(Int(minSec))–\(Int(maxSec))s)")
        print("Flags: --max-files N | --latency-only | --wer-only | --only id1,id2")
        print("")

        // Load latency audio
        let latAudio: [Float]
        let latDur: Double
        do {
            latAudio = try AudioFileLoader.load(
                url: URL(fileURLWithPath: clip), targetSampleRate: 16000)
            latDur = Double(latAudio.count) / 16000.0
            print(String(format: "Latency clip: %.2fs @ 16 kHz (%d samples)", latDur, latAudio.count))
        } catch {
            fputs("Failed to load clip \(clip): \(error)\n", stderr)
            exit(1)
        }

        var utts: [Utterance] = []
        if !latencyOnly {
            do {
                print("Loading LibriSpeech utterances…")
                utts = try loadUtterances(maxFiles: maxFiles)
                let audioSum = utts.map(\.duration).reduce(0, +)
                let words = utts.map { normalize($0.text).count }.reduce(0, +)
                print(String(
                    format: "  %d utterances · %.1fs audio · ~%d ref words",
                    utts.count, audioSum, words))
            } catch {
                fputs("WER dataset error: \(error.localizedDescription)\n", stderr)
                if werOnly { exit(1) }
                print("  Continuing with latency-only.")
            }
        }
        print("")

        let selected = engines.filter { onlyIds.isEmpty || onlyIds.contains($0.id) }
        var latResults: [LatencyResult] = []
        var werResults: [WerResult] = []

        for (i, spec) in selected.enumerated() {
            print("══════════════════════════════════════════════════════════════")
            print("[\(i + 1)/\(selected.count)] \(spec.label)")
            print("  id: \(spec.id)  kind: \(spec.kind.rawValue)")
            print("  model: \(spec.modelId)")
            if let d = spec.decoderModelId { print("  decoder: \(d)") }

            let engine: LoadedEngine
            do {
                print("  Loading…")
                engine = try await loadEngine(spec)
                print(String(
                    format: "  Loaded in %.1fs  warmup %.1fs",
                    engine.loadSeconds, engine.warmupSeconds))
            } catch {
                print("  ✗ load failed: \(error.localizedDescription)")
                latResults.append(LatencyResult(
                    id: spec.id, label: spec.label, engine: spec.kind.rawValue,
                    best: .infinity, mean: .infinity, rtf: .infinity,
                    load: 0, warmup: 0, preview: "", error: error.localizedDescription))
                if !latencyOnly, !utts.isEmpty {
                    werResults.append(WerResult(
                        id: spec.id, label: spec.label, engine: spec.kind.rawValue,
                        utterances: 0, totalAudio: 0, totalInfer: 0,
                        totalRefWords: 0, totalErrors: 0, subs: 0, ins: 0, dels: 0,
                        meanWer: 100, aggregateWer: 100, rtf: .infinity,
                        samples: [], error: error.localizedDescription))
                }
                print("")
                continue
            }

            if !werOnly {
                print("  Latency (\(latencyRuns) runs)…")
                let lr = runLatency(engine: engine, audio: latAudio, duration: latDur)
                latResults.append(lr)
                if let e = lr.error {
                    print("  ✗ latency: \(e)")
                } else {
                    print(String(
                        format: "  ✓ best %.3fs  mean %.3fs  RTF %.3f  (%.0f× realtime)",
                        lr.best, lr.mean, lr.rtf, latDur / max(lr.best, 0.001)))
                    print("  text: \(lr.preview)")
                }
            }

            if !latencyOnly, !utts.isEmpty {
                print("  WER on \(utts.count) utterances…")
                let wr = runWER(engine: engine, utts: utts)
                werResults.append(wr)
                print(String(
                    format: "  ✓ aggregate WER %.2f%%  mean %.2f%%  errors %d/%d  RTF %.3f",
                    wr.aggregateWer, wr.meanWer, wr.totalErrors, wr.totalRefWords, wr.rtf))
                if let e = wr.error { print("  note: \(e)") }
            }

            // Free GPU/ANE before next engine
            engine.unload()
            print("  Unloaded.\n")
        }

        // MARK: Summaries
        printLatencySummary(latResults, duration: latDur)
        printWerSummary(werResults)
        printCombinedRecommendation(latResults, werResults)

        // JSON dump
        writeJSON(
            host: host,
            memGB: memGB,
            clip: clip,
            latDur: latDur,
            maxFiles: maxFiles,
            lat: latResults,
            wer: werResults
        )
    }

    // MARK: - Reporting

    static func printLatencySummary(_ results: [LatencyResult], duration: Double) {
        let ok = results.filter { $0.error == nil && $0.best.isFinite }
        guard !ok.isEmpty else {
            print("\n(no latency results)")
            return
        }
        print("═══════════════════════════════════════════════════════════════")
        print(String(format: "LATENCY SUMMARY — %.1fs audio, best of %d", duration, latencyRuns))
        print("═══════════════════════════════════════════════════════════════")
        let header = pad("Model", 48) + "  Latency      RTF      Load"
        print(header)
        print(String(repeating: "─", count: 80))
        let sorted = ok.sorted { $0.best < $1.best }
        for (i, r) in sorted.enumerated() {
            let mark = i == 0 ? " ← fastest" : ""
            print(String(
                format: "%@  %6.3fs  %8.3f  %6.1fs%@",
                pad(r.label, 48), r.best, r.rtf, r.load, mark))
        }
        for r in results where r.error != nil {
            print("\(pad(r.label, 48))  FAILED: \(r.error!)")
        }
        print("")
    }

    static func printWerSummary(_ results: [WerResult]) {
        let ok = results.filter { $0.error == nil && $0.utterances > 0 }
        guard !ok.isEmpty else {
            print("(no WER results)")
            return
        }
        print("═══════════════════════════════════════════════════════════════")
        print("WER SUMMARY — LibriSpeech test-clean subset")
        print("═══════════════════════════════════════════════════════════════")
        print(pad("Model", 48) + "    WER%   Mean%  Err/Words      RTF")
        print(String(repeating: "─", count: 88))
        let sorted = ok.sorted { $0.aggregateWer < $1.aggregateWer }
        for (i, r) in sorted.enumerated() {
            let mark = i == 0 ? " ← most accurate" : ""
            let err = "\(r.totalErrors)/\(r.totalRefWords)"
            print(String(
                format: "%@  %6.2f  %6.2f  %@  %8.3f%@",
                pad(r.label, 48),
                r.aggregateWer, r.meanWer,
                pad(err, 12),
                r.rtf, mark))
        }
        for r in results where r.error != nil && r.utterances == 0 {
            print("\(pad(r.label, 48))  FAILED: \(r.error!)")
        }
        print("")
        print("S/I/D breakdown:")
        for r in sorted {
            print("  \(pad(r.label, 48))  S=\(r.subs) I=\(r.ins) D=\(r.dels)")
        }
        print("")
    }

    static func printCombinedRecommendation(_ lat: [LatencyResult], _ wer: [WerResult]) {
        let latOk = lat.filter { $0.error == nil && $0.best.isFinite }
        let werOk = wer.filter { $0.error == nil && $0.utterances > 0 }
        guard !latOk.isEmpty || !werOk.isEmpty else { return }

        print("═══════════════════════════════════════════════════════════════")
        print("COMBINED — accuracy vs speed")
        print("═══════════════════════════════════════════════════════════════")
        print(pad("Model", 48) + "   Lat(s)    WER%      RTF  Notes")
        print(String(repeating: "─", count: 90))

        let ids = Set(latOk.map(\.id)).union(werOk.map(\.id))
        var rows: [(id: String, label: String, lat: Double?, wer: Double?, rtf: Double?)] = []
        for id in ids {
            let l = latOk.first { $0.id == id }
            let w = werOk.first { $0.id == id }
            rows.append((
                id,
                l?.label ?? w?.label ?? id,
                l?.best,
                w?.aggregateWer,
                w?.rtf ?? l?.rtf
            ))
        }
        // Sort by WER then latency
        rows.sort {
            let wa = $0.wer ?? 999
            let wb = $1.wer ?? 999
            if abs(wa - wb) > 0.05 { return wa < wb }
            return ($0.lat ?? 999) < ($1.lat ?? 999)
        }

        let fastestId = latOk.min(by: { $0.best < $1.best })?.id
        let bestWerId = werOk.min(by: { $0.aggregateWer < $1.aggregateWer })?.id

        for r in rows {
            var notes: [String] = []
            if r.id == fastestId { notes.append("fastest") }
            if r.id == bestWerId { notes.append("best WER") }
            let latS = r.lat.map { String(format: "%6.3f", $0) } ?? "     —"
            let werS = r.wer.map { String(format: "%6.2f", $0) } ?? "     —"
            let rtfS = r.rtf.map { String(format: "%8.3f", $0) } ?? "       —"
            print("\(pad(r.label, 48))  \(latS)  \(werS)  \(rtfS)  \(notes.joined(separator: ", "))")
        }

        print("")
        print("Product guidance:")
        if let best = werOk.min(by: { $0.aggregateWer < $1.aggregateWer }) {
            print("  • Most accurate on this set: \(best.label) (\(String(format: "%.2f", best.aggregateWer))% WER)")
        }
        if let fast = latOk.min(by: { $0.best < $1.best }) {
            print("  • Fastest on latency clip: \(fast.label) (\(String(format: "%.3f", fast.best))s)")
        }
        // Pareto-ish: among WER within 0.5pp of best, pick fastest
        if let bestWer = werOk.map(\.aggregateWer).min() {
            let contenders = werOk.filter { $0.aggregateWer <= bestWer + 0.5 }
            let contIds = Set(contenders.map(\.id))
            if let pick = latOk.filter({ contIds.contains($0.id) }).min(by: { $0.best < $1.best }) {
                print("  • Best accuracy–speed balance (±0.5pp of best WER): \(pick.label)")
            }
        }
        print("  • CoreML hybrid/full for Qwen is about power/GPU freeness — check RTF vs pure MLX.")
        print("  • Parakeet wins speed; if quality is uneven on your speech, prefer best-WER Qwen.")
        print("")
    }

    static func writeJSON(
        host: String,
        memGB: UInt64,
        clip: String,
        latDur: Double,
        maxFiles: Int,
        lat: [LatencyResult],
        wer: [WerResult]
    ) {
        let outDir = URL(fileURLWithPath: "bench/results")
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let out = outDir.appendingPathComponent("full_suite_\(stamp).json")

        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: "\\n")
        }

        var json = "{\n"
        json += "  \"host\": \"\(esc(host))\",\n"
        json += "  \"ram_gb\": \(memGB),\n"
        json += "  \"clip\": \"\(esc(clip))\",\n"
        json += "  \"clip_duration_s\": \(latDur),\n"
        json += "  \"wer_max_files\": \(maxFiles),\n"
        json += "  \"latency\": [\n"
        for (i, r) in lat.enumerated() {
            let comma = i + 1 < lat.count ? "," : ""
            let err = r.error.map { "\"\(esc($0))\"" } ?? "null"
            json += """
                {"id":"\(esc(r.id))","label":"\(esc(r.label))","engine":"\(esc(r.engine))",\
            "best_s":\(r.best.isFinite ? String(r.best) : "null"),\
            "mean_s":\(r.mean.isFinite ? String(r.mean) : "null"),\
            "rtf":\(r.rtf.isFinite ? String(r.rtf) : "null"),\
            "load_s":\(r.load),"warmup_s":\(r.warmup),\
            "preview":"\(esc(r.preview))","error":\(err)}\(comma)\n
            """
        }
        json += "  ],\n  \"wer\": [\n"
        for (i, r) in wer.enumerated() {
            let comma = i + 1 < wer.count ? "," : ""
            let err = r.error.map { "\"\(esc($0))\"" } ?? "null"
            json += """
                {"id":"\(esc(r.id))","label":"\(esc(r.label))","engine":"\(esc(r.engine))",\
            "utterances":\(r.utterances),"total_audio_s":\(r.totalAudio),\
            "total_infer_s":\(r.totalInfer),"aggregate_wer":\(r.aggregateWer),\
            "mean_wer":\(r.meanWer),"errors":\(r.totalErrors),"ref_words":\(r.totalRefWords),\
            "subs":\(r.subs),"ins":\(r.ins),"dels":\(r.dels),\
            "rtf":\(r.rtf.isFinite ? String(r.rtf) : "null"),"error":\(err)}\(comma)\n
            """
        }
        json += "  ]\n}\n"

        do {
            try json.write(to: out, atomically: true, encoding: .utf8)
            // Also write stable latest path
            let latest = outDir.appendingPathComponent("full_suite_latest.json")
            try json.write(to: latest, atomically: true, encoding: .utf8)
            print("Wrote \(out.path)")
            print("Wrote \(latest.path)")
        } catch {
            print("Failed to write JSON: \(error)")
        }
    }

    // MARK: - Utils

    static func pad(_ s: String, _ n: Int) -> String {
        if s.count >= n { return String(s.prefix(n)) }
        return s + String(repeating: " ", count: n - s.count)
    }

    static func preview(_ text: String, limit: Int = 100) -> String {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        if t.isEmpty { return "(empty)" }
        if t.count <= limit { return t }
        return String(t.prefix(limit)) + "…"
    }

    static func parseIntFlag(_ args: [String], name: String) -> Int? {
        if let idx = args.firstIndex(of: name), idx + 1 < args.count {
            return Int(args[idx + 1])
        }
        // --max-files=50
        if let eq = args.first(where: { $0.hasPrefix("\(name)=") }) {
            return Int(eq.split(separator: "=").last.map(String.init) ?? "")
        }
        return nil
    }

    static func parseOnly(_ args: [String]) -> Set<String> {
        guard let idx = args.firstIndex(of: "--only"), idx + 1 < args.count else {
            if let eq = args.first(where: { $0.hasPrefix("--only=") }) {
                let v = eq.dropFirst("--only=".count)
                return Set(v.split(separator: ",").map(String.init))
            }
            return []
        }
        return Set(args[idx + 1].split(separator: ",").map(String.init))
    }
}
