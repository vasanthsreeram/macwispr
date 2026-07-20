import Foundation
import HuggingFace

/// On-device polish weight packs (MLX directories). User can switch in Settings.
/// Default pack (`PolishModel`) is Qwen3.5-0.8B Base full-SFT polish (not Liquid).
///
/// Weights are **never** shipped inside the app. When the user enables Local polish,
/// MacWispr downloads the pack from Hugging Face into
/// `Application Support/MacWispr/PolishModel/`. Env / Application Support / dev cache
/// paths work for offline QA — not the app bundle.
enum PolishLocalModel: String, CaseIterable, Identifiable, Codable {
    case miniCPM = "minicpm"  // rawValue kept for prefs; UI label is Qwen3.5 polish
    case liquid = "liquid"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .miniCPM:
            return "Qwen3.5-0.8B · polish SFT (MLX 4-bit)"
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
            if isAvailable {
                return "Default. Lists, cleanup, course-correction; does not answer questions. ~400 MB on disk (4-bit)."
            }
            return "Default. Lists, cleanup, course-correction; does not answer questions. Downloads ~400 MB once when you enable Local polish (not in the app install)."
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

    /// Hugging Face model id for on-demand download. `nil` = no auto-download.
    var huggingfaceRepoId: String? {
        switch self {
        case .miniCPM:
            return ProcessInfo.processInfo.environment["MACWISPR_POLISH_HF_REPO"]
                ?? "vasanth009/macwispr-qwen35-08b-polish"
        case .liquid:
            return nil
        }
    }

    /// Approximate download size shown in Settings (user-facing).
    var downloadSizeLabel: String {
        switch self {
        case .miniCPM: return "~400 MB"
        case .liquid: return "varies"
        }
    }

    /// Whether weights exist for this model on disk (complete enough to load).
    var isAvailable: Bool {
        Self.resolveDirectory(for: self) != nil
    }

    /// Whether this pack can be offered in Settings (on disk or downloadable).
    var isSelectable: Bool {
        isAvailable || huggingfaceRepoId != nil
    }

    /// Packs that appear in Settings (installed or downloadable).
    static var availableCases: [PolishLocalModel] {
        allCases.filter(\.isSelectable)
    }

    /// Application Support install directory for this pack (created on demand).
    static func applicationSupportDirectory(for model: PolishLocalModel) -> URL? {
        let fm = FileManager.default
        guard let support = try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else { return nil }
        return support
            .appendingPathComponent("MacWispr", isDirectory: true)
            .appendingPathComponent(model.resourceFolderName, isDirectory: true)
    }

    /// True if `dir` looks like a complete MLX weight pack (config + safetensors).
    static func looksLikeCompletePack(at dir: URL) -> Bool {
        let fm = FileManager.default
        let config = dir.appendingPathComponent("config.json")
        guard fm.fileExists(atPath: config.path) else { return false }
        let single = dir.appendingPathComponent("model.safetensors")
        if fm.fileExists(atPath: single.path) { return true }
        // Sharded packs
        if let contents = try? fm.contentsOfDirectory(atPath: dir.path) {
            return contents.contains { $0.hasPrefix("model-") && $0.hasSuffix(".safetensors") }
                || contents.contains { $0.hasSuffix(".safetensors") }
        }
        return false
    }

    static func resolveDirectory(for model: PolishLocalModel) -> URL? {
        let fm = FileManager.default
        if let override = ProcessInfo.processInfo.environment[model.envKey],
           !override.isEmpty
        {
            let u = URL(fileURLWithPath: override)
            if looksLikeCompletePack(at: u) { return u }
        }
        // Global override still maps to currently selected miniCPM path for back-compat.
        if model == .miniCPM,
           let override = ProcessInfo.processInfo.environment["MACWISPR_POLISH_MODEL"],
           !override.isEmpty
        {
            let u = URL(fileURLWithPath: override)
            if looksLikeCompletePack(at: u) { return u }
        }
        // Do not load from the app bundle — models are never packaged there.
        // Application Support installs (download-on-enable target)
        if let dir = applicationSupportDirectory(for: model),
           looksLikeCompletePack(at: dir)
        {
            return dir
        }
        // Dev fallbacks under known cache paths
        let home = fm.homeDirectoryForCurrentUser
        let devCandidates: [String] = {
            switch model {
            case .miniCPM:
                return [
                    // Prefer 4-bit product pack, then bf16 enum / earlier fused packs.
                    ".cache/macwispr-minicpm-bench/fused/qwen35-08b-polish-enum-4bit",
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
            if looksLikeCompletePack(at: u) { return u }
        }
        return nil
    }

    /// Download pack from Hugging Face into Application Support if missing.
    /// No-op when weights are already resolvable. Reports progress 0…1 via handler.
    @discardableResult
    static func ensureDownloaded(
        _ model: PolishLocalModel,
        progressHandler: (@Sendable (Double, String) -> Void)? = nil
    ) async throws -> URL {
        if let existing = resolveDirectory(for: model) {
            progressHandler?(1.0, "Ready · \(model.shortName)")
            return existing
        }
        guard let repoIdString = model.huggingfaceRepoId,
              let repoID = Repo.ID(rawValue: repoIdString)
        else {
            throw NSError(domain: "PolishLocalModel", code: 1, userInfo: [
                NSLocalizedDescriptionKey:
                    "Polish model not found for \(model.shortName). Enable Local polish to download, set \(model.envKey), or install under Application Support/\(model.resourceFolderName)."
            ])
        }
        guard let dest = applicationSupportDirectory(for: model) else {
            throw NSError(domain: "PolishLocalModel", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Could not create Application Support directory for polish model."
            ])
        }

        let fm = FileManager.default
        // Staging directory so a partial download never looks "complete".
        let staging = dest.deletingLastPathComponent()
            .appendingPathComponent(".\(model.resourceFolderName).download", isDirectory: true)
        try? fm.removeItem(at: staging)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)

        progressHandler?(0.02, "Downloading \(model.shortName) (\(model.downloadSizeLabel))…")

        let client = HubClient()
        _ = try await client.downloadSnapshot(
            of: repoID,
            to: staging,
            revision: "main",
            matching: [],
            progressHandler: { @MainActor progress in
                // Progress is file-count based for multi-file repos; weight is ~all of one file.
                let frac = progress.fractionCompleted
                // Map download into 0.02…0.95 so load can use the rest.
                let mapped = 0.02 + max(0, min(1, frac)) * 0.93
                let pct = Int(mapped * 100)
                progressHandler?(mapped, "Downloading \(model.shortName)… \(pct)%")
            }
        )

        guard looksLikeCompletePack(at: staging) else {
            try? fm.removeItem(at: staging)
            throw NSError(domain: "PolishLocalModel", code: 3, userInfo: [
                NSLocalizedDescriptionKey:
                    "Downloaded polish pack looks incomplete (missing config.json or weights)."
            ])
        }

        // Replace any previous install atomically enough for our needs.
        if fm.fileExists(atPath: dest.path) {
            try? fm.removeItem(at: dest)
        }
        try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.moveItem(at: staging, to: dest)

        progressHandler?(0.96, "Download complete")
        return dest
    }

    /// Remove Application Support install of this pack (not bundle / env / dev).
    static func deleteDownloaded(_ model: PolishLocalModel) throws {
        guard let dir = applicationSupportDirectory(for: model) else { return }
        let fm = FileManager.default
        if fm.fileExists(atPath: dir.path) {
            try fm.removeItem(at: dir)
        }
        let staging = dir.deletingLastPathComponent()
            .appendingPathComponent(".\(model.resourceFolderName).download", isDirectory: true)
        try? fm.removeItem(at: staging)
    }
}
