import Foundation
import Qwen3ASR
import AudioCommon

@main
struct CompareASR {
    static func main() async {
        let args = CommandLine.arguments
        let clip = args.count > 1 ? args[1] : "bench/clips/sample_10s_16k.wav"
        let modelId = args.count > 2 ? args[2] : "mlx-community/Qwen3-ASR-0.6B-8bit"
        let audio = try! AudioFileLoader.load(url: URL(fileURLWithPath: clip), targetSampleRate: 16000)
        let duration = Double(audio.count) / 16000.0
        print("clip: \(clip) (\(String(format: "%.1f", duration))s)")
        print("model: \(modelId)")
        let loadStart = CFAbsoluteTimeGetCurrent()
        let model = try! await Qwen3ASRModel.fromPretrained(modelId: modelId)
        print(String(format: "load: %.2fs", CFAbsoluteTimeGetCurrent() - loadStart))
        _ = model.transcribe(audio: [Float](repeating: 0, count: 16000), sampleRate: 16000, maxTokens: 8)
        let maxTokens = min(256, max(64, Int(duration * 25)))
        var times: [Double] = []
        var lastText = ""
        for i in 1...3 {
            let t0 = CFAbsoluteTimeGetCurrent()
            lastText = model.transcribe(audio: audio, sampleRate: 16000, maxTokens: maxTokens)
            let elapsed = CFAbsoluteTimeGetCurrent() - t0
            times.append(elapsed)
            print(String(format: "run %d: %.3fs  RTF %.3f", i, elapsed, elapsed / duration))
        }
        print(String(format: "best: %.3fs  RTF %.3f", times.min()!, times.min()! / duration))
        print("--- transcript ---")
        print(lastText)
    }
}
