import Foundation

/// Loads a JSON array of `T` from disk without ever discarding data silently.
/// Bad entries are skipped; the original bytes are preserved in a sibling
/// `<name>.corrupt-<timestamp>.json` file whenever anything was dropped.
public enum LossyJSONArrayFile {
    public struct LoadResult<T> {
        public var items: [T]
        /// Entries skipped because they failed to decode.
        public var skipped: Int
        /// Quarantine copy of the original file, if one was written.
        public var quarantineURL: URL?
        /// False when the file exists but its bytes could not be preserved or read;
        /// callers must not overwrite it.
        public var safeToOverwrite: Bool
    }

    private struct Lossy<T: Decodable>: Decodable {
        let value: T?
        init(from decoder: Decoder) throws { value = try? T(from: decoder) }
    }

    public static func decodeLossy<T: Decodable>(
        _ type: T.Type, from data: Data, decoder: JSONDecoder = JSONDecoder()
    ) throws -> (items: [T], skipped: Int) {
        let all = try decoder.decode([Lossy<T>].self, from: data)
        let items = all.compactMap(\.value)
        return (items, all.count - items.count)
    }

    public static func load<T: Decodable>(
        _ type: T.Type, from url: URL, decoder: JSONDecoder = JSONDecoder(),
        now: Date = Date(), log: (String) -> Void = { _ in }
    ) -> LoadResult<T> {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else {
            return LoadResult(items: [], skipped: 0, quarantineURL: nil, safeToOverwrite: true)
        }
        guard let data = try? Data(contentsOf: url) else {
            log("unreadable: \(url.lastPathComponent)")
            return LoadResult(items: [], skipped: 0, quarantineURL: nil, safeToOverwrite: false)
        }
        let target = quarantineURL(for: url, now: now)
        do {
            let (items, skipped) = try decodeLossy(type, from: data, decoder: decoder)
            guard skipped > 0 else {
                return LoadResult(items: items, skipped: 0, quarantineURL: nil, safeToOverwrite: true)
            }
            // Partial loss: keep original in place, write a copy first.
            let ok = (try? fm.copyItem(at: url, to: target)) != nil
            log("skipped \(skipped) bad entries in \(url.lastPathComponent); copy ok=\(ok)")
            return LoadResult(items: items, skipped: skipped, quarantineURL: ok ? target : nil, safeToOverwrite: ok)
        } catch {
            // Not a JSON array at all: move aside, start empty.
            var ok = (try? fm.moveItem(at: url, to: target)) != nil
            if !ok { ok = (try? fm.copyItem(at: url, to: target)) != nil }
            log("unparseable \(url.lastPathComponent); quarantined=\(ok)")
            return LoadResult(items: [], skipped: 0, quarantineURL: ok ? target : nil, safeToOverwrite: ok)
        }
    }

    static func quarantineURL(for url: URL, now: Date) -> URL {
        let stamp = Int(now.timeIntervalSince1970)
        let base = url.deletingPathExtension().lastPathComponent
        let dir = url.deletingLastPathComponent()
        var candidate = dir.appendingPathComponent("\(base).corrupt-\(stamp).json")
        var n = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = dir.appendingPathComponent("\(base).corrupt-\(stamp)-\(n).json")
            n += 1
        }
        return candidate
    }
}
