import Foundation
import MLX
import MLXLMCommon
import MLXLLM
import MLXHuggingFace
import Tokenizers
import HuggingFace

/// On-device MLX polish for ASR transcripts (cleanup + lists + course-correction).
///
/// Default weights: **Qwen3.5-0.8B polish structure SFT v3** (MLX 4-bit, not Liquid).
/// User can switch to optional LFM pack in Settings when present. Prompt format
/// matches train: bare `### Input:` / `### Output:` (no few-shot, no chat thinking).
///
/// Weights resolve from env → Application Support (HF download) → dev cache.
/// Production Sparkle builds do not embed the pack (~400 MB 4-bit download).
actor TextPolisher {
    /// UI label for the currently selected local pack.
    static var displayName: String {
        currentModelPreference().displayName
    }

    private var container: ModelContainer?
    private var loadedModel: PolishLocalModel?
    private var isLoading = false

    var isLoaded: Bool { container != nil }

    var activeModel: PolishLocalModel? { loadedModel }

    private static let preferenceKey = "polishLocalModel"

    static func currentModelPreference() -> PolishLocalModel {
        if let raw = UserDefaults.standard.string(forKey: preferenceKey),
           let m = PolishLocalModel(rawValue: raw),
           m.isSelectable
        {
            return m
        }
        // Default MiniCPM — never silently stick on Liquid.
        if PolishLocalModel.miniCPM.isSelectable { return .miniCPM }
        return PolishLocalModel.availableCases.first ?? .miniCPM
    }

    static func setModelPreference(_ model: PolishLocalModel) {
        UserDefaults.standard.set(model.rawValue, forKey: preferenceKey)
    }

    func unload() {
        container = nil
        loadedModel = nil
        MLXMemoryPolicy.reclaim(reason: "polish-unload")
    }

    func load(
        model: PolishLocalModel? = nil,
        progressHandler: (@Sendable (Double, String) -> Void)? = nil
    ) async throws {
        let target = model ?? Self.currentModelPreference()
        if container != nil, loadedModel == target { return }
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        // Switching packs drops the previous container.
        container = nil
        loadedModel = nil

        // Download to Application Support when missing (HF); no-op if already present.
        let dir: URL
        do {
            dir = try await PolishLocalModel.ensureDownloaded(target, progressHandler: progressHandler)
        } catch {
            throw NSError(domain: "TextPolisher", code: 1, userInfo: [
                NSLocalizedDescriptionKey:
                    "Polish model not available for \(target.shortName): \(error.localizedDescription)"
            ])
        }

        progressHandler?(0.97, "Loading \(target.shortName)")
        let loaded = try await loadModelContainer(
            from: dir, using: #huggingFaceTokenizerLoader())
        progressHandler?(1.0, "Ready · \(target.shortName)")
        self.container = loaded
        self.loadedModel = target
        Self.setModelPreference(target)
    }

    /// Polish a transcript. Returns original text on failure or tiny input.
    func polish(_ text: String) async -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return text }
        guard trimmed.split(whereSeparator: \.isWhitespace).count >= 3 else { return text }
        guard let container else { return text }

        let wordCount = trimmed.split(whereSeparator: \.isWhitespace).count
        // Lists expand with newlines; allow more room than raw word count.
        let maxTokens = min(280, max(48, wordCount * 5))
        let prompt = Self.buildPrompt(for: trimmed)

        do {
            let output: String = try await container.perform { context in
                let ids = context.tokenizer.encode(text: prompt)
                let input = LMInput(tokens: MLXArray(ids))
                let params = GenerateParameters(maxTokens: maxTokens, temperature: 0.0)
                var result = ""
                let stream = try MLXLMCommon.generate(
                    input: input,
                    cache: nil,
                    parameters: params,
                    context: context
                )
                for try await item in stream {
                    if case .chunk(let chunk) = item {
                        result += chunk
                        // Stop if model starts a new example / think block
                        if result.contains("### Input:") || result.contains("<think>") {
                            break
                        }
                    }
                }
                return result
            }
            let cleaned = sanitize(output, original: trimmed)
            // Intermediate generation buffers are free to recycle now.
            MLXMemoryPolicy.reclaim(reason: "after-polish")
            return cleaned.isEmpty ? text : cleaned
        } catch {
            NSLog("MacWispr TextPolisher (MLX) failed: \(error.localizedDescription)")
            MLXMemoryPolicy.reclaim(reason: "polish-error")
            return text
        }
    }

    /// Bare completion prompt — matches Qwen3.5 polish SFT training format.
    private static func buildPrompt(for text: String) -> String {
        "### Input:\n\(text)\n\n### Output:\n"
    }

    private func sanitize(_ output: String, original: String) -> String {
        var s = output.trimmingCharacters(in: .whitespacesAndNewlines)
        for stop in ["### Input:", "### Output:", "\n###", "<think>", "</think>", "<|im_end|>"] {
            if let r = s.range(of: stop) {
                s = String(s[..<r.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return s
    }
}
