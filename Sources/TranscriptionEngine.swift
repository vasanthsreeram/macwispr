import Foundation
import Qwen3ASR
import ParakeetASR
import SpeechVAD
import MacWisprCore
import MLX

actor TranscriptionEngine {
    private enum Backend {
        case qwen(Qwen3ASRModel)
        case parakeet(ParakeetASRModel)
    }

    private var backend: Backend?
    /// Loaded alongside Qwen for VAD-guided streaming. Unused for Parakeet.
    private var vadModel: SileroVADModel?
    private var isWarmedUp = false
    private(set) var loadedModelId: String?
    private var loadedEngine: ASRModelSize.Engine?
    /// Bumped on each load start and on unload so a finishing stale load
    /// cannot reinstall weights after the user switched provider/size.
    private var loadGeneration = 0

    /// Audio shorter than this uses a single batch pass (streaming overhead not worth it).
    private static let streamingMinSeconds: Double = 1.5

    func loadModel(
        size: ASRModelSize,
        progressHandler: @escaping @Sendable (Double, String) -> Void
    ) async throws {
        let modelId = size.modelId
        // Already on the requested model (and VAD ready for Qwen streaming).
        if backend != nil, loadedModelId == modelId {
            if size.engine == .qwenMLX, vadModel == nil {
                try await loadVAD(progressHandler: progressHandler, generation: loadGeneration)
            }
            return
        }

        loadGeneration += 1
        let generation = loadGeneration

        // Explicit unload frees weights + Metal/ANE footprint.
        releaseModel()

        // Drop incomplete/corrupt HF cache *before* load so speech-swift does not
        // treat a stub `model.safetensors` as “already downloaded”.
        ASRModelCache.prepareForLoad(size: size)
        Self.prepareGPUCacheForLoad()

        do {
            try await loadModelOnce(
                size: size,
                modelId: modelId,
                generation: generation,
                progressHandler: progressHandler
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // Common on flaky first downloads: partial weights → “file couldn’t be opened”.
            guard ASRModelCache.shouldRetryAfterPurge(error) else { throw error }
            guard generation == loadGeneration else { throw CancellationError() }
            NSLog(
                "MacWispr: ASR load failed (\(error.localizedDescription)); purging cache and re-downloading \(modelId)"
            )
            progressHandler(0.01, "Re-downloading model (previous cache was incomplete)…")
            ASRModelCache.purge(modelId: modelId)
            try await loadModelOnce(
                size: size,
                modelId: modelId,
                generation: generation,
                progressHandler: progressHandler
            )
        }
    }

    private func loadModelOnce(
        size: ASRModelSize,
        modelId: String,
        generation: Int,
        progressHandler: @escaping @Sendable (Double, String) -> Void
    ) async throws {
        switch size.engine {
        case .qwenMLX:
            progressHandler(0.02, "Loading Qwen…")
            let loaded = try await Qwen3ASRModel.fromPretrained(
                modelId: modelId
            ) { progress, status in
                // Reserve room for VAD after ASR weights.
                progressHandler(progress * 0.75, status)
            }
            guard generation == loadGeneration else {
                loaded.unload()
                throw CancellationError()
            }
            self.backend = .qwen(loaded)
            self.loadedModelId = modelId
            self.loadedEngine = .qwenMLX
            warmUpQwen(loaded)

            try await loadVAD(progressHandler: progressHandler, generation: generation)
            progressHandler(1.0, "Ready")

        case .parakeetCoreML:
            // Free VAD when not on Qwen.
            vadModel = nil
            progressHandler(0.05, "Loading Parakeet…")
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
            progressHandler(1.0, "Ready")
        }
    }

    private func loadVAD(
        progressHandler: @escaping @Sendable (Double, String) -> Void,
        generation: Int
    ) async throws {
        if vadModel != nil { return }
        progressHandler(0.78, "Loading voice activity model…")
        let vad = try await SileroVADModel.fromPretrained { progress, status in
            progressHandler(0.78 + progress * 0.2, status)
        }
        guard generation == loadGeneration else {
            throw CancellationError()
        }
        self.vadModel = vad
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
        vadModel = nil
        isWarmedUp = false
        loadedModelId = nil
        loadedEngine = nil
        Self.releaseGPUCache()
    }

    /// MLX cacheLimit defaults to the (large) memoryLimit, so `clearCache()`
    /// alone can leave ~100MB+ of reusable Metal buffers after unload.
    /// Measured: Grok-after-unload 158 MB vs cold Grok 39 MB.
    private static func releaseGPUCache() {
        Memory.cacheLimit = 0
        Memory.clearCache()
    }

    /// Inference wants a modest pool; 0 (idle) would thrash every layer.
    private static func prepareGPUCacheForLoad() {
        if Memory.cacheLimit < 256 * 1_024 * 1_024 {
            Memory.cacheLimit = 1_024 * 1_024 * 1_024
        }
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

    /// Batch transcription (Parakeet, short clips, or streaming fallback).
    /// Long captures are split into overlapping windows so GPU RAM stays O(window).
    /// - Parameter context: Optional system-prompt context (custom vocab).
    ///   Applied for Qwen3 only — Parakeet does not take a context prompt.
    func transcribe(
        samples: [Float],
        language: String? = nil,
        context: String? = nil
    ) async throws -> String {
        guard backend != nil else {
            throw TranscriptionError.modelNotLoaded
        }
        let (window, overlap) = windowParams
        if samples.count <= window {
            return try await transcribeOneWindow(
                samples: samples, language: language, context: context
            )
        }
        var parts: [String] = []
        for w in AudioChunkPlanner.windows(
            sampleCount: samples.count,
            windowSamples: window,
            overlapSamples: overlap
        ) {
            let chunk = Array(samples[w.startSample..<w.endSample])
            parts.append(
                try await transcribeOneWindow(samples: chunk, language: language, context: context)
            )
        }
        return TranscriptStitch.join(parts)
    }

    /// Same as `transcribe(samples:)` but never materializes the full session.
    func transcribe(
        ring: SampleRing,
        language: String? = nil,
        context: String? = nil
    ) async throws -> String {
        guard backend != nil else {
            throw TranscriptionError.modelNotLoaded
        }
        let (window, overlap) = windowParams
        return try await ring.transcribeWindows(
            windowSamples: window,
            overlapSamples: overlap
        ) { chunk in
            try await self.transcribeOneWindow(samples: chunk, language: language, context: context)
        }
    }

    private var windowParams: (Int, Int) {
        switch loadedEngine {
        case .parakeetCoreML:
            return (AudioChunkPlanner.parakeetWindowSamples, AudioChunkPlanner.parakeetOverlapSamples)
        default:
            return (AudioChunkPlanner.qwenWindowSamples, AudioChunkPlanner.qwenOverlapSamples)
        }
    }

    private func transcribeOneWindow(
        samples: [Float],
        language: String?,
        context: String?
    ) async throws -> String {
        guard let backend else {
            throw TranscriptionError.modelNotLoaded
        }
        switch backend {
        case .qwen(let model):
            if !isWarmedUp { warmUpQwen(model) }
            return Self.batchTranscribeQwen(
                model: model,
                samples: samples,
                language: language,
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

    /// Qwen path with VAD-guided streaming partials for perceived speed.
    ///
    /// Emits growing transcript text via `onPartial` as segments finalize (and
    /// intermediate partials while a segment is open). Falls back to a single
    /// batch pass for very short clips or if VAD finds no speech.
    ///
    /// Polish must run **after** this returns — never mid-stream.
    func transcribeStreaming(
        samples: [Float],
        language: String? = nil,
        context: String? = nil,
        onPartial: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        guard let backend else {
            throw TranscriptionError.modelNotLoaded
        }

        switch backend {
        case .parakeet:
            // Parakeet TDT is batch-only in this build.
            let text = try await transcribe(
                samples: samples, language: language, context: context)
            onPartial(text)
            return text

        case .qwen(let model):
            if !isWarmedUp { warmUpQwen(model) }

            let durationSec = Double(samples.count) / 16000.0
            // Short dictation: one shot is already sub-second; skip VAD overhead.
            if durationSec < Self.streamingMinSeconds || vadModel == nil {
                let text = Self.batchTranscribeQwen(
                    model: model,
                    samples: samples,
                    language: language,
                    context: context
                )
                onPartial(text)
                return text
            }

            let vad = vadModel!
            let maxTokens = AudioChunkPlanner.maxTokens(forSampleCount: samples.count)
            let config = StreamingASRConfig(
                maxSegmentDuration: 8.0,
                vadConfig: .sileroDefault,
                language: language,
                maxTokens: maxTokens,
                emitPartialResults: true,
                partialResultInterval: 0.9,
                context: context
            )

            let streaming = StreamingASR(asrModel: model, vadModel: vad)
            var finals: [String] = []
            var livePartial = ""

            func publish() {
                var parts = finals
                if !livePartial.isEmpty { parts.append(livePartial) }
                let combined = parts
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
                if !combined.isEmpty {
                    onPartial(combined)
                }
            }

            // Consume the stream on this actor. StreamingASR is not thread-safe;
            // keep all ASR calls serialized here.
            let stream = streaming.transcribeStream(
                audio: samples,
                sampleRate: 16000,
                config: config
            )
            for try await segment in stream {
                let trimmed = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                if segment.isFinal {
                    finals.append(trimmed)
                    livePartial = ""
                } else {
                    livePartial = trimmed
                }
                publish()
            }

            var result = finals
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            if result.isEmpty, !livePartial.isEmpty {
                result = livePartial
            }

            // VAD sometimes yields nothing on quiet/short speech — batch fallback.
            if result.isEmpty {
                result = Self.batchTranscribeQwen(
                    model: model,
                    samples: samples,
                    language: language,
                    context: context
                )
                if !result.isEmpty {
                    onPartial(result)
                }
            }

            return result
        }
    }

    private static func batchTranscribeQwen(
        model: Qwen3ASRModel,
        samples: [Float],
        language: String?,
        context: String?
    ) -> String {
        let maxTokens = AudioChunkPlanner.maxTokens(forSampleCount: samples.count)
        return model.transcribe(
            audio: samples,
            sampleRate: 16000,
            language: language,
            maxTokens: maxTokens,
            context: context
        )
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
    case outOfMemory(String)

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded: return "Model not loaded"
        case .recordingFailed: return "Recording failed"
        case .outOfMemory(let message): return message
        }
    }
}
