import Foundation
import Qwen3ASR

actor TranscriptionEngine {
    private var model: Qwen3ASRModel?
    private var isWarmedUp = false

    func loadModel(progressHandler: @escaping @Sendable (Double, String) -> Void) async throws {
        let loaded = try await Qwen3ASRModel.fromPretrained(
            modelId: "aufklarer/Qwen3-ASR-0.6B-MLX-4bit"
        ) { progress, status in
            progressHandler(progress, status)
        }
        self.model = loaded
        warmUp()
    }

    /// Compile Metal kernels so the first real dictation isn't slow.
    private func warmUp() {
        guard let model, !isWarmedUp else { return }
        let silence = [Float](repeating: 0, count: 16000)
        _ = model.transcribe(audio: silence, sampleRate: 16000, maxTokens: 8)
        isWarmedUp = true
    }

    func transcribe(samples: [Float], language: String? = nil) async throws -> String {
        guard let model = model else {
            throw TranscriptionError.modelNotLoaded
        }
        if !isWarmedUp { warmUp() }
        let durationSec = Double(samples.count) / 16000.0
        let maxTokens = min(256, max(64, Int(durationSec * 25)))
        let text = model.transcribe(
            audio: samples,
            sampleRate: 16000,
            language: language,
            maxTokens: maxTokens
        )
        return text
    }

    var isLoaded: Bool {
        model != nil
    }
}

enum TranscriptionError: LocalizedError {
    case modelNotLoaded
    case recordingFailed

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded: return "Model not loaded"
        case .recordingFailed: return "Recording failed"
        }
    }
}
