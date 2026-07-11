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
        // Do not call model.warmUp() — it feeds 1s silence, which pads to mel
        // shape 200 and fails against the fixed 3000-frame encoder.
        let silence = [Float](repeating: 0, count: 16_000)
        _ = try model.transcribeAudio(
            Self.prepareParakeetSamples(silence),
            sampleRate: 16_000
        )
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
            // Fixed-shape Core ML encoders expect mel [1, 128, 3000] only.
            // speech-swift (macOS 14 pin) still pads short audio to the nearest
            // EnumeratedShapes length (100/200/…); those smaller shapes crash
            // against the re-exported INT8 encoder. Pad/trim PCM so the mel
            // frame count lands in (2000, 3000] and padding selects 3000.
            let prepared = Self.prepareParakeetSamples(samples)
            return try model.transcribeAudio(
                prepared,
                sampleRate: 16000,
                language: language
            )
        }
    }

    /// Parakeet mel hop length (matches NeMo / speech-swift MelPreprocessor).
    private static let parakeetHopLength = 160
    /// Max mel frames the fixed-shape INT8 encoder accepts (≈30 s @ 16 kHz).
    private static let parakeetMaxMelFrames = 3000
    /// Smallest mel frame count whose enumerated pad target is 3000 (not 2000).
    private static let parakeetMinMelFramesForFullWindow = 2001

    /// Zero-pad or trim 16 kHz PCM so Parakeet’s mel length fits the fixed
    /// 3000-frame Core ML encoder without hitting a too-small enumerated shape.
    static func prepareParakeetSamples(_ samples: [Float]) -> [Float] {
        // MelPreprocessor: nFrames ≈ samples/hop + 1 (reflect-pad STFT).
        // Keep nFrames in (2000, 3000] so padMelToEnumeratedShape picks 3000.
        let minSamples = (parakeetMinMelFramesForFullWindow - 1) * parakeetHopLength
        let maxSamples = (parakeetMaxMelFrames - 1) * parakeetHopLength

        if samples.count < minSamples {
            var padded = samples
            padded.append(contentsOf: repeatElement(Float(0), count: minSamples - samples.count))
            return padded
        }
        if samples.count > maxSamples {
            // Prefer the most recent speech (dictation tail).
            return Array(samples.suffix(maxSamples))
        }
        return samples
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
