import Foundation

/// On-device Qwen3-ASR variants available in MacWispr.
enum ASRModelSize: String, CaseIterable, Identifiable, Codable {
    case small = "0.6B"
    case large = "1.7B"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .small: return "Qwen3-ASR 0.6B (8-bit)"
        case .large: return "Qwen3-ASR 1.7B (8-bit)"
        }
    }

    /// MLX 8-bit checkpoints — better quality than 4-bit with only a small latency hit.
    var modelId: String {
        switch self {
        case .small: return "mlx-community/Qwen3-ASR-0.6B-8bit"
        case .large: return "mlx-community/Qwen3-ASR-1.7B-8bit"
        }
    }

    var subtitle: String {
        switch self {
        case .small: return "~500 MB · 8-bit · fast everyday dictation"
        case .large: return "~1.5 GB · 8-bit · highest accuracy · slower (~2–3×)"
        }
    }

    var help: String {
        switch self {
        case .small:
            return "Default. 8-bit weights for better quality than 4-bit with nearly the same speed."
        case .large:
            return "Best accuracy on names, accents, and noisy audio. Larger download on first use."
        }
    }
}
