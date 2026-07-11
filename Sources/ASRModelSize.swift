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
        case .small: return "~500 MB · 8-bit · lighter · best on ≤16 GB Macs"
        case .large: return "~1.5 GB · 8-bit · higher accuracy · best on >16 GB Macs"
        }
    }

    var help: String {
        switch self {
        case .small:
            return "Faster and uses less memory. Prefer on 16 GB machines or when you want snappier dictation."
        case .large:
            return "Slightly better accuracy (names, accents, noise). Comfortable on Macs with more than 16 GB of memory."
        }
    }

    // MARK: - RAM-based default

    /// Physical system memory in bytes (`ProcessInfo`).
    static var systemMemoryBytes: UInt64 {
        ProcessInfo.processInfo.physicalMemory
    }

    /// System RAM in whole gigabytes (binary GiB, floor).
    static var systemMemoryGB: Int {
        Int(systemMemoryBytes / 1_073_741_824)
    }

    /// Macs with **more than 16 GB** default to 1.7B; 16 GB and below default to 0.6B.
    static let sixteenGigabytes: UInt64 = 16 * 1_073_741_824

    /// Recommended size for this machine (user can always override).
    static var recommendedDefault: ASRModelSize {
        systemMemoryBytes > sixteenGigabytes ? .large : .small
    }

    var isRecommendedForThisMac: Bool {
        self == Self.recommendedDefault
    }

    /// Segmented control label (marks the RAM-based recommendation).
    var pickerLabel: String {
        isRecommendedForThisMac ? "\(rawValue) · rec." : rawValue
    }

    /// Short caption for Settings (e.g. “Recommended for this Mac (32 GB)”).
    static var recommendationCaption: String {
        let gb = systemMemoryGB
        let rec = recommendedDefault
        switch rec {
        case .large:
            return "This Mac has \(gb) GB of memory — defaulting to 1.7B for higher accuracy. You can switch to 0.6B anytime."
        case .small:
            return "This Mac has \(gb) GB of memory — defaulting to 0.6B to stay light. You can try 1.7B if you want max accuracy."
        }
    }
}
