import Foundation
import Qwen3ASR
import ParakeetASR
import AudioCommon

/// Cross-engine latency bench: Qwen3-ASR (MLX) + Parakeet TDT (CoreML / ANE).
/// Nemotron MLX is covered by `bench/bench_mlx_audio.py` (mlx-audio).
@main
struct BenchLatency {
    struct QwenSpec {
        let label: String
        let modelId: String
    }

    struct ParakeetSpec {
        let label: String
        let modelId: String
    }

    /// Default app-relevant set. Pass `--all-qwen` for the full 4-model Qwen matrix.
    static let defaultQwen: [QwenSpec] = [
        QwenSpec(label: "Qwen3 0.6B MLX-8bit (app default)", modelId: "mlx-community/Qwen3-ASR-0.6B-8bit"),
        QwenSpec(label: "Qwen3 1.7B MLX-8bit", modelId: "mlx-community/Qwen3-ASR-1.7B-8bit"),
    ]

    static let allQwen: [QwenSpec] = [
        QwenSpec(label: "Qwen3 0.6B MLX-4bit", modelId: "aufklarer/Qwen3-ASR-0.6B-MLX-4bit"),
        QwenSpec(label: "Qwen3 0.6B MLX-8bit", modelId: "mlx-community/Qwen3-ASR-0.6B-8bit"),
        QwenSpec(label: "Qwen3 1.7B MLX-4bit", modelId: "aufklarer/Qwen3-ASR-1.7B-MLX-4bit"),
        QwenSpec(label: "Qwen3 1.7B MLX-8bit", modelId: "mlx-community/Qwen3-ASR-1.7B-8bit"),
    ]

    /// Parakeet TDT **v3** (multilingual, 25 EU langs) via speech-swift CoreML/ANE.
    /// Same generation FluidVoice uses for batch dictation (FluidAudio CoreML ports).
    /// v2 English-only is only on the MLX path (`bench/bench_mlx_audio.py --models parakeet`).
    static let parakeetModels: [ParakeetSpec] = [
        ParakeetSpec(
            label: "Parakeet TDT v3 CoreML INT4 (multilingual)",
            modelId: ParakeetASRModel.defaultModelId),
        ParakeetSpec(
            label: "Parakeet TDT v3 CoreML INT8 (multilingual)",
            modelId: ParakeetASRModel.int8ModelId),
    ]

    struct Result {
        let label: String
        let engine: String
        let best: Double
        let rtf: Double
        let load: Double
        let preview: String
    }

    static func main() async {
        let args = Array(CommandLine.arguments.dropFirst())
        let allQwenFlag = args.contains("--all-qwen")
        let skipParakeet = args.contains("--qwen-only")
        let skipQwen = args.contains("--parakeet-only")
        let clip = args.first(where: { !$0.hasPrefix("--") })
            ?? "bench/clips/speech_12s_16k.wav"

        let machine = ProcessInfo.processInfo.hostName
        let audio: [Float]
        do {
            audio = try AudioFileLoader.load(
                url: URL(fileURLWithPath: clip), targetSampleRate: 16000)
        } catch {
            fputs("Failed to load audio \(clip): \(error)\n", stderr)
            exit(1)
        }
        let duration = Double(audio.count) / 16000.0
        let silence = [Float](repeating: 0, count: 16000)

        print("╔══════════════════════════════════════════════════════════════╗")
        print("║     ASR Latency Bench — Qwen3 (MLX) + Parakeet (CoreML)      ║")
        print("╚══════════════════════════════════════════════════════════════╝")
        print("Host: \(machine)")
        print("Clip: \(clip) (\(String(format: "%.2f", duration))s @ 16 kHz)")
        print("Method: load once → warmup → 3 timed runs → best latency + text preview")
        print("Flags: --all-qwen | --qwen-only | --parakeet-only")
        print("")

        var results: [Result] = []

        if !skipQwen {
            let qwenModels = allQwenFlag ? allQwen : defaultQwen
            for spec in qwenModels {
                print("▸ \(spec.label)")
                print("  engine: MLX  model: \(spec.modelId)")
                do {
                    let loadStart = CFAbsoluteTimeGetCurrent()
                    let model = try await Qwen3ASRModel.fromPretrained(modelId: spec.modelId)
                    let loadTime = CFAbsoluteTimeGetCurrent() - loadStart

                    let warmupStart = CFAbsoluteTimeGetCurrent()
                    _ = model.transcribe(audio: silence, sampleRate: 16000, maxTokens: 8)
                    let warmupTime = CFAbsoluteTimeGetCurrent() - warmupStart

                    var times: [Double] = []
                    var lastText = ""
                    let maxTokens = min(256, max(64, Int(duration * 25)))
                    for i in 1...3 {
                        let t0 = CFAbsoluteTimeGetCurrent()
                        lastText = model.transcribe(
                            audio: audio, sampleRate: 16000, maxTokens: maxTokens)
                        let elapsed = CFAbsoluteTimeGetCurrent() - t0
                        times.append(elapsed)
                        print(String(format: "  run %d: %.3fs  (RTF %.3f)", i, elapsed, elapsed / duration))
                    }

                    let best = times.min()!
                    results.append(Result(
                        label: spec.label,
                        engine: "MLX",
                        best: best,
                        rtf: best / duration,
                        load: loadTime,
                        preview: Self.preview(lastText)
                    ))
                    print(String(
                        format: "  ✓ best: %.3fs  RTF %.3f  load: %.1fs  warmup: %.1fs",
                        best, best / duration, loadTime, warmupTime))
                    print("  text: \(Self.preview(lastText))")
                } catch {
                    print("  ✗ skipped: \(error.localizedDescription)")
                }
                print("")
            }
        }

        if !skipParakeet {
            for spec in parakeetModels {
                print("▸ \(spec.label)")
                print("  engine: CoreML/ANE  model: \(spec.modelId)")
                do {
                    let loadStart = CFAbsoluteTimeGetCurrent()
                    let model = try await ParakeetASRModel.fromPretrained(modelId: spec.modelId)
                    let loadTime = CFAbsoluteTimeGetCurrent() - loadStart

                    let warmupStart = CFAbsoluteTimeGetCurrent()
                    try model.warmUp()
                    let warmupTime = CFAbsoluteTimeGetCurrent() - warmupStart

                    var times: [Double] = []
                    var lastText = ""
                    for i in 1...3 {
                        let t0 = CFAbsoluteTimeGetCurrent()
                        lastText = try model.transcribeAudio(audio, sampleRate: 16000)
                        let elapsed = CFAbsoluteTimeGetCurrent() - t0
                        times.append(elapsed)
                        print(String(format: "  run %d: %.3fs  (RTF %.3f)", i, elapsed, elapsed / duration))
                    }

                    let best = times.min()!
                    results.append(Result(
                        label: spec.label,
                        engine: "CoreML",
                        best: best,
                        rtf: best / duration,
                        load: loadTime,
                        preview: Self.preview(lastText)
                    ))
                    print(String(
                        format: "  ✓ best: %.3fs  RTF %.3f  load: %.1fs  warmup: %.1fs",
                        best, best / duration, loadTime, warmupTime))
                    print("  text: \(Self.preview(lastText))")
                } catch {
                    print("  ✗ skipped: \(error.localizedDescription)")
                }
                print("")
            }
        }

        guard !results.isEmpty else {
            fputs("No successful engine runs.\n", stderr)
            exit(2)
        }

        let fastest = results.min(by: { $0.best < $1.best })!
        let maxBar = results.map(\.best).max()!

        print("═══════════════════════════════════════════════════════════════")
        print("SUMMARY — inference latency for \(String(format: "%.1f", duration))s audio")
        print("═══════════════════════════════════════════════════════════════")
        print("")
        print(String(format: "%-40s %8s %8s %8s  %s", "Model", "Latency", "RTF", "Load", "Chart"))
        print(String(repeating: "─", count: 88))

        for r in results.sorted(by: { $0.best < $1.best }) {
            let barLen = Int((r.best / maxBar) * 20)
            let bar = String(repeating: "█", count: max(1, barLen))
            let marker = r.label == fastest.label ? " ← fastest" : ""
            print(String(
                format: "%-40s %6.2fs %8.3f %6.1fs  %@%@",
                r.label, r.best, r.rtf, r.load, bar, marker))
        }

        print("")
        print(String(
            format: "Winner: %@ (%.2fs for %.1fs audio, %.1f× realtime)",
            fastest.label, fastest.best, duration, duration / fastest.best))
        print("")
        print("Notes:")
        print("  • Qwen3 = MLX GPU (Metal). Parakeet here = CoreML Neural Engine.")
        print("  • FluidVoice Parakeet/Nemotron path is also CoreML via FluidAudio.")
        print("  • Official Nemotron MLX (mlx-community) is benched with:")
        print("      ./bench/bench_mlx_audio.py \(clip)")
        print("  • Parakeet MLX (mlx-community/parakeet-tdt-*) is typically slower than CoreML.")
    }

    private static func preview(_ text: String, limit: Int = 100) -> String {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        if t.isEmpty { return "(empty)" }
        if t.count <= limit { return t }
        return String(t.prefix(limit)) + "…"
    }
}
