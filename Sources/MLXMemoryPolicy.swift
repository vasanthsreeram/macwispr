import Foundation
import MLX

/// Keeps MLX Metal buffer growth in check.
///
/// MLX recycles freed GPU buffers in a pool. On high-RAM Macs the default
/// cache limit tracks the large recommended working set, so live partials
/// (many intermediate tensor sizes) can push Activity Monitor footprint to
/// 10+ GB while real model weights are only ~1–2 GB.
///
/// Policy:
/// - Cap free-buffer **cache** at 1.5 GB (weights stay allocated separately).
/// - Drop unused cache after dictation and on model unload.
enum MLXMemoryPolicy {
    /// Max free Metal buffers MLX may keep for reuse (~1.5 GiB).
    static let cacheLimitBytes: Int = Int(1.5 * 1024 * 1024 * 1024)

    private static var didApply = false

    /// Call once early in app launch (before/around first model load).
    static func apply() {
        guard !didApply else { return }
        didApply = true
        Memory.cacheLimit = cacheLimitBytes
        // Drop anything already pooled from a previous partial init path.
        Memory.clearCache()
        logSnapshot(prefix: "MLX memory policy applied (cacheLimit=1.5 GiB)")
    }

    /// Free unused MLX GPU buffers. Safe to call often; active model weights
    /// and in-flight arrays are not discarded.
    static func reclaim(reason: String) {
        // Ensure limit is set even if apply() was skipped (e.g. tests).
        if !didApply {
            apply()
        } else if Memory.cacheLimit != cacheLimitBytes {
            Memory.cacheLimit = cacheLimitBytes
        }
        Memory.clearCache()
        logSnapshot(prefix: "MLX reclaim (\(reason))")
    }

    private static func logSnapshot(prefix: String) {
        let snap = Memory.snapshot()
        let activeMB = Double(snap.activeMemory) / 1_048_576
        let cacheMB = Double(snap.cacheMemory) / 1_048_576
        let peakMB = Double(snap.peakMemory) / 1_048_576
        NSLog(
            "MacWispr: %@ — active=%.0f MB cache=%.0f MB peak=%.0f MB",
            prefix,
            activeMB,
            cacheMB,
            peakMB
        )
    }
}
