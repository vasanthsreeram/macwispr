import Foundation
import HuggingFace

/// On-device polish weight packs (MLX directories). User can switch in Settings.
/// Default pack (`PolishModel`) is Qwen3.5-0.8B structure-v3 SFT polish (MLX 4-bit).
///
/// Weights are **never** shipped inside the app. When the user enables Local polish,
/// MacWispr downloads the pack from Hugging Face into
/// `Application Support/MacWispr/PolishModel/`. Env / Application Support / dev cache
/// paths work for offline QA — not the app bundle.
///
/// Default HF repo (v3 test / product candidate):
/// `vasanth009/macwispr-polish-qwen35-08b-v3-4bit`
/// Older production enum pack remains at `vasanth009/macwispr-qwen35-08b-polish`
/// (override with `MACWISPR_POLISH_HF_REPO` if needed).
enum PolishLocalModel: String, CaseIterable, Identifiable, Codable {
    case miniCPM = "minicpm"  // rawValue kept for prefs; UI label is Qwen3.5 polish
    case liquid = "liquid"

    /// Marker written into Application Support installs so repo switches re-download.
    static let hfSourceMarkerFilename = ".macwispr-hf-repo"

    /// Product default HF id for the Qwen polish pack (4-bit).
    static let defaultQwenPolishHFRepo = "vasanth009/macwispr-polish-qwen35-08b-v3-4bit"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .miniCPM:
            return "Qwen3.5-0.8B · polish v3 SFT (MLX 4-bit)"
        case .liquid:
            return "LFM2.5-350M · course LoRA (MLX)"
        }
    }

    var shortName: String {
        switch self {
        case .miniCPM: return "Qwen3.5 polish v3"
        case .liquid: return "Liquid LFM"
        }
    }

    var help: String {
        switch self {
        case .miniCPM:
            if isAvailable {
                return "Default. Structure/list polish SFT v3; lists, cleanup, course-correction; does not answer questions. ~400 MB on disk (4-bit)."
            }
            return "Default. Structure/list polish SFT v3; lists, cleanup, course-correction; does not answer questions. Downloads ~400 MB once when you enable Local polish (not in the app install)."
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
                ?? Self.defaultQwenPolishHFRepo
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

    /// Short title for Models catalog.
    var catalogTitle: String {
        switch self {
        case .miniCPM: return "Qwen3.5 Polish v3"
        case .liquid: return "Liquid LFM Polish"
        }
    }

    var catalogSubtitle: String {
        switch self {
        case .miniCPM:
            return "Post-dictation cleanup · structure/lists v3 · course-correction · on-device 4-bit"
        case .liquid:
            return "Optional smaller course-correction pack (if installed)"
        }
    }

    var catalogBadge: String {
        switch self {
        case .miniCPM: return "LLM · 4-bit"
        case .liquid: return "LLM · LoRA"
        }
    }

    /// Catalog rows (downloadable or already on disk).
    static var catalogCases: [PolishLocalModel] {
        allCases.filter(\.isSelectable)
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

    /// HF repo id recorded when this Application Support pack was installed, if any.
    static func installedHFSource(at dir: URL) -> String? {
        let marker = dir.appendingPathComponent(hfSourceMarkerFilename)
        guard let raw = try? String(contentsOf: marker, encoding: .utf8) else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func writeHFSourceMarker(at dir: URL, repoId: String) {
        let marker = dir.appendingPathComponent(hfSourceMarkerFilename)
        try? repoId.write(to: marker, atomically: true, encoding: .utf8)
    }

    /// True when Application Support install matches the currently configured HF repo.
    /// Missing marker on a downloadable pack is treated as stale (forces re-pull after repo switch).
    static func applicationSupportMatchesConfiguredRepo(for model: PolishLocalModel) -> Bool {
        guard let dir = applicationSupportDirectory(for: model),
              looksLikeCompletePack(at: dir)
        else { return false }
        guard let expected = model.huggingfaceRepoId else {
            // No auto-download pack — any complete install is fine.
            return true
        }
        return installedHFSource(at: dir) == expected
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
        // Application Support installs (download-on-enable target). Prefer only when
        // the pack was pulled for the currently configured HF repo (or has no HF id).
        if applicationSupportMatchesConfiguredRepo(for: model),
           let dir = applicationSupportDirectory(for: model)
        {
            return dir
        }
        // Dev fallbacks under known cache paths
        let home = fm.homeDirectoryForCurrentUser
        let devCandidates: [String] = {
            switch model {
            case .miniCPM:
                return [
                    // Prefer latest structure SFT 4-bit, then earlier structure / enum packs.
                    ".cache/macwispr-minicpm-bench/fused/qwen35-08b-polish-structure-v3-4bit",
                    ".cache/macwispr-minicpm-bench/fused/qwen35-08b-polish-structure-v2-4bit",
                    ".cache/macwispr-minicpm-bench/fused/qwen35-08b-polish-structure-4bit",
                    ".cache/macwispr-minicpm-bench/fused/qwen35-08b-polish-enum-4bit",
                    ".cache/macwispr-minicpm-bench/fused/qwen35-08b-polish-enum",
                    ".cache/macwispr-minicpm-bench/fused/qwen35-08b-polish-structure-v2-dpo-4bit",
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

    /// Download pack from Hugging Face into Application Support if missing or stale.
    /// No-op when weights are already resolvable for the configured repo / env / dev path.
    /// Reports progress 0…1 via handler.
    @discardableResult
    static func ensureDownloaded(
        _ model: PolishLocalModel,
        progressHandler: (@Sendable (Double, String) -> Void)? = nil
    ) async throws -> URL {
        // Prefer env override or an Application Support install that matches the
        // configured HF repo. Do **not** short-circuit on a stale App Support pack
        // or on a dev-cache fallback when HF is configured — those would block upgrades.
        if let envPath = ProcessInfo.processInfo.environment[model.envKey],
           !envPath.isEmpty
        {
            let u = URL(fileURLWithPath: envPath)
            if looksLikeCompletePack(at: u) {
                progressHandler?(1.0, "Ready · \(model.shortName)")
                return u
            }
        }
        if model == .miniCPM,
           let envPath = ProcessInfo.processInfo.environment["MACWISPR_POLISH_MODEL"],
           !envPath.isEmpty
        {
            let u = URL(fileURLWithPath: envPath)
            if looksLikeCompletePack(at: u) {
                progressHandler?(1.0, "Ready · \(model.shortName)")
                return u
            }
        }
        if applicationSupportMatchesConfiguredRepo(for: model),
           let dest = applicationSupportDirectory(for: model)
        {
            progressHandler?(1.0, "Ready · \(model.shortName)")
            return dest
        }

        guard let repoIdString = model.huggingfaceRepoId,
              let repoID = Repo.ID(rawValue: repoIdString)
        else {
            // No HF auto-download: fall back to any resolvable path (dev cache, etc.).
            if let existing = resolveDirectory(for: model) {
                progressHandler?(1.0, "Ready · \(model.shortName)")
                return existing
            }
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

        writeHFSourceMarker(at: staging, repoId: repoIdString)

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
