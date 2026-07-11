import Foundation
import Qwen3ASR
import ParakeetASR

actor TranscriptionEngine {
    private enum Backend {
        case qwen(Qwen3ASRModel)
        case parakeet(ParakeetASRModel)
    }

    private var backend: Backend?
    private var isWarmedUp = false
    private(set) var loadedModelId: String?
    private var loadedEngine: ASRModelSize.Engine?
    /// Bumped on each load start and on unload so a finishing stale download
    /// cannot reinstall weights after the user switched provider/size.
    private var loadGeneration = 0

    func loadModel(
        size: ASRModelSize,
        progressHandler: @escaping @Sendable (Double, String) -> Void
    ) async throws {
        let modelId = size.modelId
        // Already on the requested model.
        if backend != nil, loadedModelId == modelId {
            return
        }

        loadGeneration += 1
        let generation = loadGeneration

        // Explicit unload frees weights + Metal/ANE footprint.
        releaseModel()

        switch size.engine {
        case .qwenMLX:
            let loaded = try await Qwen3ASRModel.fromPretrained(
                modelId: modelId
            ) { progress, status in
                progressHandler(progress, status)
            }
            guard generation == loadGeneration else {
                loaded.unload()
                throw CancellationError()
            }
            self.backend = .qwen(loaded)
            self.loadedModelId = modelId
            self.loadedEngine = .qwenMLX
            warmUpQwen(loaded)

        case .parakeetCoreML:
            progressHandler(0.05, "Downloading Parakeet…")
            let loaded = try await ParakeetASRModel.fromPretrained(
                modelId: modelId
            ) { progress, status in
                progressHandler(progress, status)
            }
            guard generation == loadGeneration else {
                loaded.unload()
                throw CancellationError()
            }
            self.backend = .parakeet(loaded)
            self.loadedModelId = modelId
            self.loadedEngine = .parakeetCoreML
            try warmUpParakeet(loaded)
        }
    }

    /// Legacy entry that resolves size from known model IDs.
    func loadModel(
        modelId: String,
        progressHandler: @escaping @Sendable (Double, String) -> Void
    ) async throws {
        let size = ASRModelSize.allCases.first { $0.modelId == modelId }
            ?? .recommendedDefault
        try await loadModel(size: size, progressHandler: progressHandler)
    }

    func unloadModel() {
        loadGeneration += 1
        releaseModel()
    }

    private func releaseModel() {
        switch backend {
        case .qwen(let model):
            model.unload()
        case .parakeet(let model):
            model.unload()
        case .none:
            break
        }
        backend = nil
        isWarmedUp = false
        loadedModelId = nil
        loadedEngine = nil
    }

    private func warmUpQwen(_ model: Qwen3ASRModel) {
        guard !isWarmedUp else { return }
        let silence = [Float](repeating: 0, count: 16000)
        _ = model.transcribe(audio: silence, sampleRate: 16000, maxTokens: 8)
        isWarmedUp = true
    }

    private func warmUpParakeet(_ model: ParakeetASRModel) throws {
        guard !isWarmedUp else { return }
        try model.warmUp()
        isWarmedUp = true
    }

    /// - Parameter context: Optional system-prompt context (custom vocab).
    ///   Applied for Qwen3 only — Parakeet does not take a context prompt.
    func transcribe(
        samples: [Float],
        language: String? = nil,
        context: String? = nil
    ) async throws -> String {
        guard let backend else {
            throw TranscriptionError.modelNotLoaded
        }

        switch backend {
        case .qwen(let model):
            if !isWarmedUp { warmUpQwen(model) }
            let durationSec = Double(samples.count) / 16000.0
            let maxTokens = min(256, max(64, Int(durationSec * 25)))
            return model.transcribe(
                audio: samples,
                sampleRate: 16000,
                language: language,
                maxTokens: maxTokens,
                context: context
            )

        case .parakeet(let model):
            if !isWarmedUp { try warmUpParakeet(model) }
            // Protocol helper or direct API — language is optional (auto-detect).
            return try model.transcribeAudio(
                samples,
                sampleRate: 16000,
                language: language
            )
        }
    }

    var isLoaded: Bool {
        backend != nil
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
