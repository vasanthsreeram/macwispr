import Foundation

/// On-device polish weight packs (MLX directories). User can switch in Settings.
/// Default pack (`PolishModel`) is Qwen3.5-0.8B Base full-SFT polish (not Liquid).
enum PolishLocalModel: String, CaseIterable, Identifiable, Codable {
    case miniCPM = "minicpm"  // rawValue kept for prefs; UI label is Qwen3.5 polish
    case liquid = "liquid"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .miniCPM:
            return "Qwen3.5-0.8B · polish SFT (MLX)"
        case .liquid:
            return "LFM2.5-350M · course LoRA (MLX)"
        }
    }

    var shortName: String {
        switch self {
        case .miniCPM: return "Qwen3.5 polish"
        case .liquid: return "Liquid LFM"
        }
    }

    var help: String {
        switch self {
        case .miniCPM:
            return "Default. Lists, cleanup, course-correction; does not answer questions. Bundled ~1.4 GB."
        case .liquid:
            return "Optional Liquid LFM pack (if installed). Smaller / older course-correction specialist."
        }
    }

    /// Resource folder name inside the app bundle (or Application Support).
    var resourceFolderName: String {
        switch self {
        case .miniCPM: return "PolishModel"
        case .liquid: return "PolishModel-LFM"
        }
    }

    /// Env override for this pack.
    var envKey: String {
        switch self {
        case .miniCPM: return "MACWISPR_POLISH_MODEL"
        case .liquid: return "MACWISPR_POLISH_MODEL_LFM"
        }
    }

    /// Whether weights exist for this model on disk.
    var isAvailable: Bool {
        Self.resolveDirectory(for: self) != nil
    }

    static var availableCases: [PolishLocalModel] {
        allCases.filter(\.isAvailable)
    }

    static func resolveDirectory(for model: PolishLocalModel) -> URL? {
        let fm = FileManager.default
        if let override = ProcessInfo.processInfo.environment[model.envKey],
           !override.isEmpty
        {
            let u = URL(fileURLWithPath: override)
            if fm.fileExists(atPath: u.path) { return u }
        }
        // Global override still maps to currently selected miniCPM path for back-compat.
        if model == .miniCPM,
           let override = ProcessInfo.processInfo.environment["MACWISPR_POLISH_MODEL"],
           !override.isEmpty
        {
            let u = URL(fileURLWithPath: override)
            if fm.fileExists(atPath: u.path) { return u }
        }
        if let bundled = Bundle.main.url(forResource: model.resourceFolderName, withExtension: nil),
           fm.fileExists(atPath: bundled.path)
        {
            return bundled
        }
        // Application Support installs (optional second packs)
        if let support = try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ) {
            let dir = support
                .appendingPathComponent("MacWispr", isDirectory: true)
                .appendingPathComponent(model.resourceFolderName, isDirectory: true)
            if fm.fileExists(atPath: dir.path) { return dir }
        }
        // Dev fallbacks under known cache paths
        let home = fm.homeDirectoryForCurrentUser
        let devCandidates: [String] = {
            switch model {
            case .miniCPM:
                return [
                    // Prefer newest fused pack first (enum generalize lists → targeted → 500-only).
                    ".cache/macwispr-minicpm-bench/fused/qwen35-08b-polish-enum",
                    ".cache/macwispr-minicpm-bench/fused/qwen35-08b-polish-targeted",
                    ".cache/macwispr-minicpm-bench/fused/qwen35-08b-polish-500",
                    ".cache/macwispr-minicpm-bench/fused/minicpm5-polish-lora-fused",
                ]
            case .liquid:
                return [
                    "Documents/macwispr/bench/polish_finetune/fused/sotto-format-sft-fused",
                    "Documents/macwispr/bench/polish_finetune/fused/sotto-lc-ft-clean-fused",
                ]
            }
        }()
        for rel in devCandidates {
            let u = home.appendingPathComponent(rel)
            if fm.fileExists(atPath: u.path) { return u }
        }
        return nil
    }
}
