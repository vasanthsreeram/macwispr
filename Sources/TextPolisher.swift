import Foundation
import Qwen3Chat

/// On-device LLM polish for ASR transcripts (grammar / punctuation / structure).
///
/// Uses Qwen3-0.6B-Chat (CoreML) from speech-swift — same stack as ASR, ~300 MB,
/// Neural Engine + GPU. Loaded lazily when the user enables polishing.
actor TextPolisher {
    static let modelId = "aufklarer/Qwen3-0.6B-Chat-CoreML"
    static let displayName = "Qwen3-0.6B-Chat (CoreML)"

    private var model: Qwen3ChatModel?
    private var isLoading = false

    var isLoaded: Bool { model != nil }

    private static let systemPrompt = """
        You are a careful editor for voice dictation transcripts.
        Fix grammar, punctuation, capitalization, and sentence structure.
        Keep the original meaning and wording as close as possible.
        Do not add explanations, quotes, or commentary.
        Output only the corrected transcript.
        """

    func load(progressHandler: (@Sendable (Double, String) -> Void)? = nil) async throws {
        if model != nil { return }
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        let loaded = try await Qwen3ChatModel.fromPretrained(
            modelId: Self.modelId,
            quantization: .int4
        ) { progress, status in
            progressHandler?(progress, status)
        }
        self.model = loaded
    }

    /// Polish a transcript. Returns the original text on failure or empty input.
    func polish(_ text: String) async -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return text }
        // Skip tiny fragments — not worth LLM latency.
        guard trimmed.split(whereSeparator: \.isWhitespace).count >= 3 else { return text }

        guard let model else { return text }

        // Cap generation roughly to input length so we don't ramble.
        let wordCount = trimmed.split(whereSeparator: \.isWhitespace).count
        let maxTokens = min(256, max(32, wordCount * 3))
        let sampling = ChatSamplingConfig(
            temperature: 0.2,
            topK: 20,
            topP: 0.85,
            maxTokens: maxTokens,
            repetitionPenalty: 1.05
        )

        do {
            let messages = [
                ChatMessage(role: .system, content: Self.systemPrompt),
                ChatMessage(role: .user, content: trimmed),
            ]
            let result = try model.generate(messages: messages, sampling: sampling)
            let cleaned = sanitize(result, original: trimmed)
            return cleaned.isEmpty ? text : cleaned
        } catch {
            NSLog("MacWispr TextPolisher: \(error.localizedDescription)")
            return text
        }
    }

    /// Strip common model junk (quotes, labels, empty lines).
    private func sanitize(_ output: String, original: String) -> String {
        var s = output.trimmingCharacters(in: .whitespacesAndNewlines)

        // Drop a single surrounding quote pair.
        if (s.hasPrefix("\"") && s.hasSuffix("\"")) || (s.hasPrefix("'") && s.hasSuffix("'")),
           s.count > 1
        {
            s = String(s.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // If the model prefixed with "Corrected:" / "Transcript:" strip it.
        for prefix in ["Corrected:", "Transcript:", "Output:", "Here is the corrected text:"] {
            if s.lowercased().hasPrefix(prefix.lowercased()) {
                s = String(s.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        // Reject wildly longer rewrites (hallucination guard).
        if s.count > max(original.count * 3, original.count + 80) {
            return original
        }

        return s
    }
}
