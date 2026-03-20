import Foundation
import Qwen3ASR

actor TranscriptionEngine {
    private var model: Qwen3ASRModel?

    func loadModel(progressHandler: @escaping @Sendable (Double, String) -> Void) async throws {
        let loaded = try await Qwen3ASRModel.fromPretrained(
            modelId: "aufklarer/Qwen3-ASR-0.6B-MLX-4bit"
        ) { progress, status in
            progressHandler(progress, status)
        }
        self.model = loaded
    }

    func transcribe(samples: [Float], language: String? = nil) async throws -> String {
        guard let model = model else {
            throw TranscriptionError.modelNotLoaded
        }
        let text = model.transcribe(
            audio: samples,
            sampleRate: 16000,
            language: language,
            maxTokens: 448
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
