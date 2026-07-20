import Foundation
import AudioCommon

/// On-disk integrity helpers for speech-swift Hugging Face caches.
///
/// Qwen 0.6B / 1.7B downloads can leave a partial `model.safetensors` after a
/// flaky network drop. speech-swift’s existence check only looks for *any*
/// `.safetensors` file, so the next launch skips re-download and MLX fails with
/// Cocoa’s “The file couldn’t be opened.”
enum ASRModelCache {
    /// Conservative minimum size for a usable weight file (bytes).
    /// Real HF sizes: ~0.6B-8bit ≈ 1.0 GB, ~1.7B-8bit ≈ 2.3 GB.
    private static let minWeightBytes: [ASRModelSize: Int64] = [
        .small: 700_000_000,
        .large: 1_800_000_000,
        .parakeetInt4: 50_000_000,
        .parakeetInt8: 50_000_000,
    ]

    /// Resolve the cache directory speech-swift would use for this model id.
    static func directory(for modelId: String) -> URL? {
        try? HuggingFaceDownloader.getCacheDirectory(for: modelId)
    }

    /// True when the cache looks complete enough to load without a re-download.
    static func looksComplete(size: ASRModelSize) -> Bool {
        guard let dir = directory(for: size.modelId) else { return false }
        switch size.engine {
        case .qwenMLX:
            return qwenPackLooksComplete(at: dir, minWeight: minWeightBytes[size] ?? 700_000_000)
        case .parakeetCoreML:
            return parakeetPackLooksComplete(at: dir)
        }
    }

    /// Delete the model’s cache folder (and incomplete Hub staging) so the next
    /// `fromPretrained` re-downloads cleanly.
    static func purge(modelId: String) {
        let fm = FileManager.default
        if let dir = directory(for: modelId), fm.fileExists(atPath: dir.path) {
            try? fm.removeItem(at: dir)
            NSLog("MacWispr: purged ASR cache at \(dir.path)")
        }
        // Also drop legacy flat cache key if present.
        if let base = fm.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("qwen3-speech", isDirectory: true)
        {
            let flat = base.appendingPathComponent(
                HuggingFaceDownloader.sanitizedCacheKey(for: modelId),
                isDirectory: true
            )
            if fm.fileExists(atPath: flat.path) {
                try? fm.removeItem(at: flat)
                NSLog("MacWispr: purged legacy ASR cache at \(flat.path)")
            }
        }
    }

    /// If the on-disk pack is partial/corrupt, purge it before load.
    static func prepareForLoad(size: ASRModelSize) {
        guard let dir = directory(for: size.modelId) else { return }
        let fm = FileManager.default
        guard fm.fileExists(atPath: dir.path) else { return }
        if !looksComplete(size: size) {
            NSLog("MacWispr: incomplete ASR pack for \(size.modelId) — purging before re-download")
            purge(modelId: size.modelId)
        }
    }

    /// Errors that usually mean a broken download / unreadable weight file.
    static func shouldRetryAfterPurge(_ error: Error) -> Bool {
        let text = (error as NSError).localizedDescription.lowercased()
          + " " + String(describing: error).lowercased()
        let needles = [
            "couldn't be opened",
            "could not be opened",
            "couldn't be opened",
            "file doesn’t exist",
            "file doesn't exist",
            "no such file",
            "failed to open",
            "unable to open",
            "mmap",
            "truncated",
            "unexpected end",
            "invalid header",
            "failed to load",
            "not a valid",
            "corrupted",
            "corrupt",
            "errno = 2",
            "errno=2",
        ]
        return needles.contains { text.contains($0) }
    }

    // MARK: - Private

    private static func qwenPackLooksComplete(at dir: URL, minWeight: Int64) -> Bool {
        let fm = FileManager.default
        let requiredNames = ["config.json", "vocab.json", "merges.txt"]
        for name in requiredNames {
            let u = dir.appendingPathComponent(name)
            guard fm.fileExists(atPath: u.path) else { return false }
            if (try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0 < 8 {
                return false
            }
        }
        // Any .safetensors — but large enough (partials are the failure mode).
        guard let contents = try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return false }

        let weights = contents.filter { $0.pathExtension == "safetensors" }
        guard !weights.isEmpty else { return false }

        var total: Int64 = 0
        for w in weights {
            let size = (try? w.resourceValues(forKeys: [.fileSizeKey]).fileSize).map { Int64($0) } ?? 0
            if size < 1_000_000 { return false } // tiny stub / incomplete write
            total += size
        }
        return total >= minWeight
    }

    private static func parakeetPackLooksComplete(at dir: URL) -> Bool {
        let fm = FileManager.default
        // speech-swift expects compiled Core ML packages under the cache dir.
        let candidates = ["encoder.mlmodelc", "decoder.mlmodelc", "joint.mlmodelc"]
        var found = 0
        for name in candidates {
            let u = dir.appendingPathComponent(name)
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: u.path, isDirectory: &isDir), isDir.boolValue {
                found += 1
            }
        }
        // Also accept .mlpackage trees used by some exports.
        if found >= 2 { return true }
        if let contents = try? fm.contentsOfDirectory(atPath: dir.path) {
            let pkgs = contents.filter { $0.hasSuffix(".mlmodelc") || $0.hasSuffix(".mlpackage") }
            return pkgs.count >= 2
        }
        return false
    }
}
