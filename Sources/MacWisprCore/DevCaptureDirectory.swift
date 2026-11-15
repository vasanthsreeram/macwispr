import Foundation

/// File operations behind the local dev-capture folder (audio + transcripts).
public enum DevCaptureDirectory {
    /// Number of capture sub-folders.
    public static func count(in root: URL) -> Int {
        let fm = FileManager.default
        guard let kids = try? fm.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        return kids.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }.count
    }

    /// Remove everything inside `root` (the folder itself stays).
    public static func clearAll(in root: URL) {
        let fm = FileManager.default
        guard let kids = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return }
        for url in kids { try? fm.removeItem(at: url) }
    }
}
