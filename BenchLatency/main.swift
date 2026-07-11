import Foundation
import Qwen3ASR
import AudioCommon

struct ModelSpec {
    let label: String
    let modelId: String
}

@main
struct BenchLatency {
    static let defaultModels: [ModelSpec] = [
        ModelSpec(label: "0.6B 4bit (aufklarer)", modelId: "aufklarer/Qwen3-ASR-0.6B-MLX-4bit"),
        ModelSpec(label: "0.6B 8bit (mlx-community)", modelId: "mlx-community/Qwen3-ASR-0.6B-8bit"),
        ModelSpec(label: "1.7B 4bit (aufklarer)", modelId: "aufklarer/Qwen3-ASR-1.7B-MLX-4bit"),
        ModelSpec(label: "1.7B 8bit (mlx-community)", modelId: "mlx-community/Qwen3-ASR-1.7B-8bit"),
    ]

    static func main() async {
        let clip = CommandLine.arguments.count > 1 && !CommandLine.arguments[1].hasPrefix("--")
            ? CommandLine.arguments[1]
            : "bench/clips/sample_10s_16k.wav"

        let machine = ProcessInfo.processInfo.hostName
        let audio = try! AudioFileLoader.load(
            url: URL(fileURLWithPath: clip), targetSampleRate: 16000)
        let duration = Double(audio.count) / 16000.0
        let silence = [Float](repeating: 0, count: 16000)

        print("╔══════════════════════════════════════════════════════════════╗")
        print("║           Qwen3-ASR Latency Benchmark (MLX / 16kHz)          ║")
        print("╚══════════════════════════════════════════════════════════════╝")
        print("Host: \(machine)")
        print("Clip: \(clip) (\(String(format: "%.1f", duration))s)")
        print("Method: load once → Metal warmup → 3 timed runs → best")
        print("")

        var results: [(label: String, best: Double, rtf: Double, load: Double)] = []

        for spec in defaultModels {
            print("▸ \(spec.label)")
            print("  model: \(spec.modelId)")

            do {
                let loadStart = CFAbsoluteTimeGetCurrent()
                let model = try await Qwen3ASRModel.fromPretrained(modelId: spec.modelId)
                let loadTime = CFAbsoluteTimeGetCurrent() - loadStart

                let warmupStart = CFAbsoluteTimeGetCurrent()
                _ = model.transcribe(audio: silence, sampleRate: 16000, maxTokens: 8)
                let warmupTime = CFAbsoluteTimeGetCurrent() - warmupStart

                var times: [Double] = []
                for i in 1...3 {
                    let t0 = CFAbsoluteTimeGetCurrent()
                    _ = model.transcribe(
                        audio: audio, sampleRate: 16000,
                        maxTokens: min(256, max(64, Int(duration * 25)))
                    )
                    let elapsed = CFAbsoluteTimeGetCurrent() - t0
                    times.append(elapsed)
                    print(String(format: "  run %d: %.3fs  (RTF %.3f)", i, elapsed, elapsed / duration))
                }

                let best = times.min()!
                let rtf = best / duration
                results.append((spec.label, best, rtf, loadTime))
                print(String(format: "  ✓ best: %.3fs  RTF %.3f  load: %.1fs  warmup: %.1fs",
                             best, rtf, loadTime, warmupTime))
            } catch {
                print("  ✗ skipped: \(error.localizedDescription)")
            }
            print("")
        }

        guard !results.isEmpty else { return }

        let fastest = results.min(by: { $0.best < $1.best })!
        let maxBar = results.map(\.best).max()!

        print("═══════════════════════════════════════════════════════════════")
        print("SUMMARY — inference latency for \(String(format: "%.0f", duration))s audio")
        print("═══════════════════════════════════════════════════════════════")
        print("")
        print(String(format: "%-36s %8s %8s %s", "Model", "Latency", "RTF", "Chart"))
        print(String(repeating: "─", count: 72))

        for r in results.sorted(by: { $0.best < $1.best }) {
            let barLen = Int((r.best / maxBar) * 24)
            let bar = String(repeating: "█", count: max(1, barLen))
            let marker = r.label == fastest.label ? " ← fastest" : ""
            print(String(format: "%-36s %6.2fs %8.3f  %@%@", r.label, r.best, r.rtf, bar, marker))
        }

        print("")
        print(String(format: "Winner: %@ (%.2fs for %.0fs audio, %.1f× realtime)",
                     fastest.label, fastest.best, duration, duration / fastest.best))
        print("")
        print("Note: HF PyTorch models (Qwen/Qwen3-ASR-*) are not benchmarked here.")
        print("They use MPS and run slower than realtime — not suitable for dictation.")
    }
}