import Foundation
import ParakeetASR

/// On-device ASR variants available in MacWispr (Qwen3 MLX + Parakeet CoreML).
enum ASRModelSize: String, CaseIterable, Identifiable, Codable {
    case small = "0.6B"
    case large = "1.7B"
    /// Legacy raw value (was INT4). Maps to the fixed-shape INT8 encoder.
    case parakeetInt4 = "Parakeet-INT4"
    /// Primary Parakeet option — Core ML INT8, fixed 30s mel window.
    case parakeetInt8 = "Parakeet-INT8"

    var id: String { rawValue }

    /// Runtime backend used by `TranscriptionEngine`.
    enum Engine: String {
        case qwenMLX
        case parakeetCoreML
    }

    var engine: Engine {
        switch self {
        case .small, .large: return .qwenMLX
        case .parakeetInt4, .parakeetInt8: return .parakeetCoreML
        }
    }

    var displayName: String {
        switch self {
        case .small: return "Qwen3-ASR 0.6B (MLX 8-bit)"
        case .large: return "Qwen3-ASR 1.7B (MLX 8-bit)"
        case .parakeetInt4: return "Parakeet TDT v3 (CoreML INT8)"
        case .parakeetInt8: return "Parakeet TDT v3 (CoreML INT8)"
        }
    }

    /// Compact label for dashboard / toolbar chips.
    var shortName: String {
        switch self {
        case .small: return "Qwen 0.6B"
        case .large: return "Qwen 1.7B"
        case .parakeetInt4, .parakeetInt8: return "Parakeet INT8"
        }
    }

    /// SF Symbol for the engine class.
    var dashboardSymbol: String {
        switch engine {
        case .qwenMLX: return "cpu"
        case .parakeetCoreML: return "brain.head.profile"
        }
    }

    /// Models offered in the dashboard quick-switch menu (INT4 legacy hidden).
    static var dashboardChoices: [ASRModelSize] {
        [.small, .large, .parakeetInt8]
    }

    /// HuggingFace model identifier used by speech-swift.
    ///
    /// The INT4 HF repo was retired; both picker values load the INT8 fixed-shape
    /// encoder (`1×128×3000` mel frames ≈ 30s). Short clips are padded in
    /// `TranscriptionEngine` so Core ML accepts them.
    var modelId: String {
        switch self {
        case .small: return "mlx-community/Qwen3-ASR-0.6B-8bit"
        case .large: return "mlx-community/Qwen3-ASR-1.7B-8bit"
        // Prefer speech-swift’s constant when present; fall back to the HF id.
        case .parakeetInt4, .parakeetInt8:
            return ParakeetASRModel.int8ModelId
        }
    }

    var subtitle: String {
        switch self {
        case .small: return "~500 MB · GPU (MLX) · lighter · best on ≤16 GB"
        case .large: return "~1.5 GB · GPU (MLX) · higher accuracy · best on >16 GB"
        case .parakeetInt4, .parakeetInt8:
            return "~Neural Engine · INT8 · fixed 30s window · multilingual"
        }
    }

    var help: String {
        switch self {
        case .small:
            return "Qwen3 on the GPU. Faster and uses less memory — good for 16 GB Macs."
        case .large:
            return "Qwen3 on the GPU. Better accuracy on names, accents, and noise."
        case .parakeetInt4, .parakeetInt8:
            return "NVIDIA Parakeet TDT v3 on the Neural Engine (Core ML INT8). Fixed 30-second mel window; shorter clips are zero-padded automatically."
        }
    }

    /// Whether custom vocabulary context is injected into this model.
    var supportsContext: Bool {
        switch engine {
        case .qwenMLX: return true
        case .parakeetCoreML: return false
        }
    }

    // MARK: - RAM-based default (Qwen only)

    static var systemMemoryBytes: UInt64 {
        ProcessInfo.processInfo.physicalMemory
    }

    static var systemMemoryGB: Int {
        Int(systemMemoryBytes / 1_073_741_824)
    }

    static let sixteenGigabytes: UInt64 = 16 * 1_073_741_824

    /// First-run default: Qwen 1.7B when RAM > 16 GB, else Qwen 0.6B.
    /// Parakeet is opt-in (user picks it in Settings).
    static var recommendedDefault: ASRModelSize {
        systemMemoryBytes > sixteenGigabytes ? .large : .small
    }

    var isRecommendedForThisMac: Bool {
        self == Self.recommendedDefault
    }

    var pickerLabel: String {
        if isRecommendedForThisMac {
            return "\(displayName) · recommended"
        }
        return displayName
    }

    static var recommendationCaption: String {
        let gb = systemMemoryGB
        switch recommendedDefault {
        case .large:
            return "This Mac has \(gb) GB — Qwen 1.7B is recommended. Parakeet runs on the Neural Engine if you prefer speed."
        case .small:
            return "This Mac has \(gb) GB — Qwen 0.6B is recommended. Parakeet (ANE) is also available."
        case .parakeetInt4, .parakeetInt8:
            return "This Mac has \(gb) GB of memory."
        }
    }
}
