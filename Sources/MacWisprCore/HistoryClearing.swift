import Foundation

/// "Clear History" must also remove dev-capture audio + transcripts.
public enum HistoryClearing {
    public static func clear(clearEntries: () -> Void, devCaptureRoot: URL) {
        clearEntries()
        DevCaptureDirectory.clearAll(in: devCaptureRoot)
    }
}
