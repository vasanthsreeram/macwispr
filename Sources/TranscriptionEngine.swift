import Foundation
import Qwen3ASR
import AudioCommon
import MLX
import MLXNN

actor TranscriptionEngine {
    private var model: Qwen3ASRModel?
    private var tokenizer: Qwen3Tokenizer?
    private var isWarmedUp = false
    private let modelId = "aufklarer/Qwen3-ASR-0.6B-MLX-4bit"

    func loadModel(progressHandler: @escaping @Sendable (Double, String) -> Void) async throws {
        let loaded = try await Qwen3ASRModel.fromPretrained(
            modelId: modelId
        ) { progress, status in
            progressHandler(progress, status)
        }
        self.model = loaded

        // Own tokenizer so we can decode tokens incrementally while generating.
        let cacheDir = try HuggingFaceDownloader.getCacheDirectory(for: modelId)
        let vocabPath = cacheDir.appendingPathComponent("vocab.json")
        if FileManager.default.fileExists(atPath: vocabPath.path) {
            let tok = Qwen3Tokenizer()
            try tok.load(from: vocabPath)
            self.tokenizer = tok
        }

        warmUp()
    }

    /// Compile Metal kernels so the first real dictation isn't slow.
    private func warmUp() {
        guard let model, !isWarmedUp else { return }
        let silence = [Float](repeating: 0, count: 16000)
        _ = model.transcribe(audio: silence, sampleRate: 16000, maxTokens: 8)
        isWarmedUp = true
    }

    /// Non-streaming one-shot (used by benchmarks / fallback).
    func transcribe(samples: [Float], language: String? = nil) async throws -> String {
        try await transcribeStreaming(samples: samples, language: language, onPartial: { _ in })
    }

    /// Autoregressive decode with partial text callbacks as tokens arrive.
    /// Makes the wait feel faster — the floating indicator can show words live.
    func transcribeStreaming(
        samples: [Float],
        language: String? = nil,
        onPartial: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        guard let model else {
            throw TranscriptionError.modelNotLoaded
        }
        if !isWarmedUp { warmUp() }

        let durationSec = Double(samples.count) / 16000.0
        let maxTokens = min(256, max(64, Int(durationSec * 25)))

        // Prefer our streaming path when we have a tokenizer + text decoder.
        if let tokenizer, model.textDecoder != nil {
            let text = generateStreaming(
                model: model,
                tokenizer: tokenizer,
                audio: samples,
                sampleRate: 16000,
                language: language,
                maxTokens: maxTokens,
                onPartial: onPartial
            )
            return text
        }

        // Fallback: library one-shot (no live tokens).
        let text = model.transcribe(
            audio: samples,
            sampleRate: 16000,
            language: language,
            maxTokens: maxTokens
        )
        onPartial(text)
        return text
    }

    var isLoaded: Bool {
        model != nil
    }

    // MARK: - Streaming generation
    // Mirrors Qwen3ASRModel.generateText but emits decoded text as tokens arrive.

    private func generateStreaming(
        model: Qwen3ASRModel,
        tokenizer: Qwen3Tokenizer,
        audio: [Float],
        sampleRate: Int,
        language: String?,
        maxTokens: Int,
        onPartial: @escaping @Sendable (String) -> Void
    ) -> String {
        let textDecoder = model.textDecoder!

        // Mel → audio embeds
        let melFeatures = model.featureExtractor.process(audio, sampleRate: sampleRate)
        let batchedFeatures = melFeatures.expandedDimensions(axis: 0)
        var audioEmbeds = model.audioEncoder(batchedFeatures)
        audioEmbeds = audioEmbeds.expandedDimensions(axis: 0)

        // Special token IDs (same as speech-swift Qwen3ASR)
        let imStartId: Int32 = 151644
        let imEndId: Int32 = 151645
        let audioStartId: Int32 = 151669
        let audioEndId: Int32 = 151670
        let audioPadId: Int32 = 151676
        let asrTextId: Int32 = 151704
        let newlineId: Int32 = 198
        let systemId: Int32 = 8948
        let userId: Int32 = 872
        let assistantId: Int32 = 77091
        let eosId = Int32(Qwen3ASRTokens.eosTokenId)

        let numAudioTokens = audioEmbeds.dim(1)

        var inputIds: [Int32] = []
        inputIds.append(contentsOf: [imStartId, systemId, newlineId])
        inputIds.append(contentsOf: [imEndId, newlineId])
        inputIds.append(contentsOf: [imStartId, userId, newlineId, audioStartId])

        let audioStartIndex = inputIds.count
        for _ in 0..<numAudioTokens {
            inputIds.append(audioPadId)
        }
        let audioEndIndex = inputIds.count

        inputIds.append(contentsOf: [audioEndId, imEndId, newlineId])
        inputIds.append(contentsOf: [imStartId, assistantId, newlineId])

        if let lang = language {
            let langTokens = tokenizer.encode("language \(lang)")
            inputIds.append(contentsOf: langTokens.map { Int32($0) })
        }
        inputIds.append(asrTextId)

        let inputIdsTensor = MLXArray(inputIds).expandedDimensions(axis: 0)
        var inputEmbeds = textDecoder.embedTokens(inputIdsTensor)

        let audioEmbedsTyped = audioEmbeds.asType(inputEmbeds.dtype)
        let beforeAudio = inputEmbeds[0..., 0..<audioStartIndex, 0...]
        let afterAudio = inputEmbeds[0..., audioEndIndex..., 0...]
        inputEmbeds = concatenated([beforeAudio, audioEmbedsTyped, afterAudio], axis: 1)

        var cache: [(MLXArray, MLXArray)]? = nil
        var generatedTokens: [Int32] = []

        var (hiddenStates, newCache) = textDecoder(inputsEmbeds: inputEmbeds, cache: cache)
        cache = newCache

        let seqLen = hiddenStates.dim(1)
        let lastHidden = hiddenStates[0..., (seqLen - 1)..<seqLen, 0...]
        var logits = textDecoder.embedTokens.asLinear(lastHidden)
        var nextToken = argMax(logits, axis: -1).squeezed().item(Int32.self)
        generatedTokens.append(nextToken)

        var lastEmitted = ""
        var lastWordCount = 0

        func emitIfUseful() {
            let raw = cleanASRText(tokenizer.decode(tokens: generatedTokens.map { Int($0) }))
            // Emit on every new complete word, or when text grew by several chars.
            let words = raw.split { $0.isWhitespace }.count
            let grewWord = words > lastWordCount
            let grewChunk = raw.count >= lastEmitted.count + 4
            if grewWord || grewChunk || raw != lastEmitted && raw.count > lastEmitted.count {
                lastEmitted = raw
                lastWordCount = words
                onPartial(raw)
            }
        }

        if nextToken != eosId {
            emitIfUseful()
        }

        for _ in 1..<maxTokens {
            if nextToken == eosId { break }

            let tokenEmbeds = textDecoder.embedTokens(MLXArray([nextToken]).expandedDimensions(axis: 0))
            (hiddenStates, newCache) = textDecoder(inputsEmbeds: tokenEmbeds, cache: cache)
            cache = newCache

            let lastHiddenNext = hiddenStates[0..., (-1)..., .ellipsis]
            logits = textDecoder.embedTokens.asLinear(lastHiddenNext)
            nextToken = argMax(logits, axis: -1).squeezed().item(Int32.self)
            generatedTokens.append(nextToken)

            if nextToken != eosId {
                emitIfUseful()
            }
        }

        let finalText = cleanASRText(tokenizer.decode(tokens: generatedTokens.map { Int($0) }))
        if finalText != lastEmitted {
            onPartial(finalText)
        }
        return finalText
    }

    private func cleanASRText(_ rawText: String) -> String {
        var text = rawText
        if let range = text.range(of: "<asr_text>") {
            text = String(text[range.upperBound...])
        }
        // Drop trailing incomplete special tokens
        text = text.replacingOccurrences(of: "<|im_end|>", with: "")
        text = text.replacingOccurrences(of: "<|endoftext|>", with: "")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
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
