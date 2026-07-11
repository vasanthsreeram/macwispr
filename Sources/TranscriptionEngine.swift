import Foundation
import Qwen3ASR

actor TranscriptionEngine {
    private var model: Qwen3ASRModel?
    private var isWarmedUp = false
    private(set) var loadedModelId: String?
    /// Bumped on each load start and on unload so a finishing stale download
    /// cannot reinstall weights after the user switched provider/size.
    private var loadGeneration = 0

    func loadModel(
        modelId: String,
        progressHandler: @escaping @Sendable (Double, String) -> Void
    ) async throws {
        // Already on the requested model.
        if model != nil, loadedModelId == modelId {
            return
        }

        loadGeneration += 1
        let generation = loadGeneration

        // Explicit unload frees weights + MLX Metal buffer cache. Merely nilling
        // the reference leaves multi‑GB GPU footprint resident (issue #12).
        releaseModel()

        let loaded = try await Qwen3ASRModel.fromPretrained(
            modelId: modelId
        ) { progress, status in
            progressHandler(progress, status)
        }

        // Superseded by unloadModel() or a newer loadModel() — free orphaned load.
        guard generation == loadGeneration else {
            loaded.unload()
            throw CancellationError()
        }

        self.model = loaded
        self.loadedModelId = modelId
        warmUp()
    }

    func unloadModel() {
        loadGeneration += 1
        releaseModel()
    }

    /// Drop weights and return Metal buffers via speech-swift `unload()` → `Memory.clearCache()`.
    private func releaseModel() {
        if let model {
            model.unload()
        }
        model = nil
        isWarmedUp = false
        loadedModelId = nil
    }

    /// Compile Metal kernels so the first real dictation isn't slow.
    private func warmUp() {
        guard let model, !isWarmedUp else { return }
        let silence = [Float](repeating: 0, count: 16000)
        _ = model.transcribe(audio: silence, sampleRate: 16000, maxTokens: 8)
        isWarmedUp = true
    }

    /// - Parameter context: Optional system-prompt context (custom vocab / domain terms).
    ///   Qwen3-ASR injects this as background knowledge so rare names and jargon
    ///   are more likely to be recognized correctly.
    func transcribe(
        samples: [Float],
        language: String? = nil,
        context: String? = nil
    ) async throws -> String {
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
            maxTokens: maxTokens,
            context: context
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
