import Foundation
import ParakeetASR

/// On-device ASR variants available in MacWispr (Qwen3 MLX + Parakeet CoreML).
enum ASRModelSize: String, CaseIterable, Identifiable, Codable {
    case small = "0.6B"
    /// Legacy raw value (was INT4). Maps to the fixed-shape INT8 encoder.
    case parakeetInt4 = "Parakeet-INT4"
    /// Primary Parakeet option — Core ML INT8, fixed 30s mel window.
    case parakeetInt8 = "Parakeet-INT8"
    /// Moondream ternary Parakeet TDT v3 (178 MB), run by the Photon sidecar.
    case parakeetRedux = "Parakeet-Redux"

    var id: String { rawValue }

    /// Runtime backend used by `TranscriptionEngine`.
    enum Engine: String {
        case qwenMLX
        case parakeetCoreML
        case photonParakeet
    }

    var engine: Engine {
        switch self {
        case .small: return .qwenMLX
        case .parakeetInt4, .parakeetInt8: return .parakeetCoreML
        case .parakeetRedux: return .photonParakeet
        }
    }

    /// User-facing name (Settings, dashboard menu, load status).
    /// Language coverage is the main decision cue — not backend jargon.
    var displayName: String {
        switch self {
        case .small: return "Qwen 0.6B (En + Asian)"
        case .parakeetInt4, .parakeetInt8: return "Parakeet v3 (En + EU)"
        case .parakeetRedux: return "Parakeet Redux (En + EU)"
        }
    }

    /// Compact label under the Local chip on the dashboard.
    var shortName: String {
        displayName
    }

    /// SF Symbol for the engine class.
    var dashboardSymbol: String {
        switch engine {
        case .qwenMLX: return "cpu"
        case .parakeetCoreML, .photonParakeet: return "brain.head.profile"
        }
    }

    /// Models offered in the dashboard quick-switch menu (INT4 legacy hidden).
    static var dashboardChoices: [ASRModelSize] {
        [.small, .parakeetInt8, .parakeetRedux]
    }

    /// HuggingFace model identifier used by speech-swift.
    ///
    /// The INT4 HF repo was retired; both picker values load the INT8 fixed-shape
    /// encoder (`1×128×3000` mel frames ≈ 30s). Short clips are padded in
    /// `TranscriptionEngine` so Core ML accepts them.
    var modelId: String {
        switch self {
        case .small: return "mlx-community/Qwen3-ASR-0.6B-8bit"
        // Prefer speech-swift’s constant when present; fall back to the HF id.
        case .parakeetInt4, .parakeetInt8:
            return ParakeetASRModel.int8ModelId
        case .parakeetRedux: return "moondream/parakeet-redux"
        }
    }

    var subtitle: String {
        switch self {
        case .small: return "English + Asian languages · GPU · lighter · best on ≤16 GB"
        case .parakeetInt4, .parakeetInt8:
            return "English + European languages · Neural Engine · very fast"
        case .parakeetRedux:
            return "English + European languages · 1.58-bit · Metal GPU · tiny download"
        }
    }

    var help: String {
        switch self {
        case .small:
            return "Qwen3 0.6B on the GPU. Strong English and Asian language coverage; lighter memory footprint."
        case .parakeetInt4, .parakeetInt8:
            return "Parakeet TDT v3 on the Neural Engine. English + European languages; live draft while you speak, final pass on release."
        case .parakeetRedux:
            return "Moondream Parakeet Redux: a 1.58-bit ternary Parakeet TDT v3 (178 MB) run with Photon on the Metal GPU. English + European languages; final pass on release."
        }
    }

    /// Whether custom vocabulary context is injected into this model.
    var supportsContext: Bool {
        switch engine {
        case .qwenMLX: return true
        case .parakeetCoreML, .photonParakeet: return false
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

    /// Product default: Qwen **0.6B** (lighter RAM / download; live partials still apply).
    /// Parakeet remains opt-in.
    static var recommendedDefault: ASRModelSize {
        .small
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
        return "This Mac has \(gb) GB — default is Qwen 0.6B (lighter). Switch to Parakeet (ANE) or Parakeet Redux for speed."
    }

    // MARK: - Catalog (Settings → Models)

    /// Short catalog title (SuperWhisper-style list row).
    var catalogTitle: String {
        switch self {
        case .small: return "Qwen 0.6B"
        case .parakeetInt4, .parakeetInt8: return "Parakeet v3"
        case .parakeetRedux: return "Parakeet Redux"
        }
    }

    /// Language / region chip.
    var languageBadge: String {
        switch self {
        case .small: return "En + Asian"
        case .parakeetInt4, .parakeetInt8, .parakeetRedux: return "En + EU"
        }
    }

    /// Approximate download size for the catalog UI.
    var downloadSizeLabel: String {
        switch self {
        case .small: return "~1.0 GB"
        case .parakeetInt4, .parakeetInt8: return "~600 MB"
        case .parakeetRedux: return "~180 MB + runtime"
        }
    }

    /// Whether this pack is fully present under the HF cache.
    var isDownloaded: Bool {
        ASRModelCache.looksComplete(size: self)
    }
}

/// Floating listening UI style (SuperWhisper-style Classic / Mini / None).
enum RecordingWindowStyle: String, CaseIterable, Identifiable, Codable {
    case classic = "classic"
    case mini = "mini"
    case none = "none"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .classic: return "Classic"
        case .mini: return "Mini"
        case .none: return "None"
        }
    }

    var help: String {
        switch self {
        case .classic:
            return "Full floating card with live draft transcript while you speak."
        case .mini:
            return "Compact Listening timer only — no live text card."
        case .none:
            return "No floating recording window. Menu bar status still updates."
        }
    }

    var symbolName: String {
        switch self {
        case .classic: return "rectangle.and.pencil.and.ellipsis"
        case .mini: return "capsule"
        case .none: return "eye.slash"
        }
    }
}

/// Liquid Glass look for the floating recording window (macOS 26+).
/// Mirrors System Settings → Appearance → Liquid Glass (Clear / Tinted).
enum LiquidGlassStyle: String, CaseIterable, Identifiable, Codable {
    case clear = "clear"
    case tinted = "tinted"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .clear: return "Clear"
        case .tinted: return "Tinted"
        }
    }
}
