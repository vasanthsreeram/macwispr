import Foundation
import MLX
import MLXLMCommon
import MLXLLM
import MLXHuggingFace
import Tokenizers
import HuggingFace

/// On-device MLX polish for ASR transcripts (cleanup + lists + course-correction).
///
/// Default weights: **Qwen3.5-0.8B polish SFT** (not Liquid). User can switch to
/// optional LFM pack in Settings when present. Prompt format matches train:
/// bare `### Input:` / `### Output:` (no few-shot, no chat thinking).
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
           m.isAvailable
        {
            return m
        }
        // Default MiniCPM — never silently stick on Liquid.
        if PolishLocalModel.miniCPM.isAvailable { return .miniCPM }
        return PolishLocalModel.availableCases.first ?? .miniCPM
    }

    static func setModelPreference(_ model: PolishLocalModel) {
        UserDefaults.standard.set(model.rawValue, forKey: preferenceKey)
    }

    func unload() {
        container = nil
        loadedModel = nil
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

        guard let dir = PolishLocalModel.resolveDirectory(for: target) else {
            throw NSError(domain: "TextPolisher", code: 1, userInfo: [
                NSLocalizedDescriptionKey:
                    "Polish model not found for \(target.shortName). Bundle \(target.resourceFolderName) or set \(target.envKey)."
            ])
        }
        progressHandler?(0.1, "Loading \(target.shortName)")
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
            return cleaned.isEmpty ? text : cleaned
        } catch {
            NSLog("MacWispr TextPolisher (MLX) failed: \(error.localizedDescription)")
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
        if (s.hasPrefix("\"") && s.hasSuffix("\"")) || (s.hasPrefix("'") && s.hasSuffix("'")),
           s.count > 1
        {
            s = String(s.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        for prefix in ["Corrected:", "Transcript:", "Output:", "Cleaned:", "Rewrite:"] {
            if s.lowercased().hasPrefix(prefix.lowercased()) {
                s = String(s.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        // Reject meta reasoning / chain-of-thought — not legitimate polished starts.
        let low = s.lowercased()
        if low.hasPrefix("i need") || low.hasPrefix("let me") || low.hasPrefix("the user")
            || low.hasPrefix("okay, let's") || low.hasPrefix("first, i ")
        {
            return original
        }
        if s.count > max(original.count * 4, original.count + 200) {
            return original
        }
        // Near-identical to input → model failed to format; keep original
        // only if it didn't at least introduce list markers.
        return s
    }
}
