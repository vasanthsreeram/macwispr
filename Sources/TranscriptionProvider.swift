import Foundation

/// Where speech is converted to text.
enum TranscriptionProvider: String, CaseIterable, Identifiable, Codable {
    case local = "Local"
    case openAI = "OpenAI"
    case elevenLabs = "ElevenLabs"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .local: return "On-device (Local)"
        case .openAI: return "OpenAI"
        case .elevenLabs: return "ElevenLabs"
        }
    }

    var subtitle: String {
        switch self {
        case .local:
            return "Private · runs on Apple Silicon · no API key"
        case .openAI:
            return "Whisper / GPT-4o Transcribe · bring your OpenAI key"
        case .elevenLabs:
            return "Scribe v2 · bring your ElevenLabs key"
        }
    }

    var help: String {
        switch self {
        case .local:
            return "Default. Audio never leaves your Mac. Best for privacy and offline use."
        case .openAI:
            return "Uses OpenAI’s audio transcriptions API (gpt-4o-mini-transcribe). Your key is stored in the macOS Keychain only."
        case .elevenLabs:
            return "Uses ElevenLabs Speech-to-Text (scribe_v2). Your key is stored in the macOS Keychain only."
        }
    }

    var requiresNetwork: Bool {
        self != .local
    }
}

/// Optional post-transcription polish engine.
enum PolishProvider: String, CaseIterable, Identifiable, Codable {
    case off = "Off"
    case local = "Local"
    case openAI = "OpenAI"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .off: return "Off"
        case .local: return "Local LLM"
        case .openAI: return "OpenAI"
        }
    }

    var help: String {
        switch self {
        case .off:
            return "Default. Inserts speech-to-text as-is (optional first-letter capitalize only). No polish model."
        case .local:
            return "Optional. On-device Qwen3.5 polish v3 (lists, structure, course-correction). Downloads ~400 MB once if not already installed — not in the app update. Off by default."
        case .openAI:
            return "Optional. Uses your OpenAI key with a small chat model. Requires network."
        }
    }
}
