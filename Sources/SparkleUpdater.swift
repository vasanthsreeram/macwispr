import AppKit
import Sparkle

/// Owns the process-wide Sparkle updater for MacWispr.
///
/// Feed URL and EdDSA public key come from Info.plist (`SUFeedURL`, `SUPublicEDKey`).
/// Only the packaged `.app` (via `scripts/build-app.sh`) ships those keys; bare
/// `swift build` binaries skip starting the updater so local dev stays quiet.
@MainActor
final class SparkleUpdater {
    static let shared = SparkleUpdater()

    /// Standard Sparkle controller (nil when Info.plist has no feed URL).
    private(set) var controller: SPUStandardUpdaterController?

    private init() {
        guard let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              !feed.isEmpty,
              !feed.contains("example.com")
        else {
            NSLog("MacWispr: Sparkle not started (no SUFeedURL in Info.plist — expected for bare SPM builds)")
            return
        }

        // startingUpdater: true begins the automatic background schedule (default ~24h).
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        NSLog("MacWispr: Sparkle updater started (feed: \(feed))")
    }

    /// User-initiated “Check for Updates…” (menu bar / About).
    func checkForUpdates() {
        guard let controller else {
            // Dev / unpackaged binary: send users to releases instead of failing silently.
            if let url = URL(string: "https://github.com/vasanthsreeram/macwispr/releases/latest") {
                NSWorkspace.shared.open(url)
            }
            return
        }
        controller.checkForUpdates(nil)
    }

    var canCheckForUpdates: Bool {
        controller?.updater.canCheckForUpdates ?? true
    }
}
