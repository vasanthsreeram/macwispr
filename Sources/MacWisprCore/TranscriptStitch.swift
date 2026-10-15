import Foundation

/// Join overlapping chunk transcripts by dropping a duplicated word prefix.
public enum TranscriptStitch {
    public static func join(_ parts: [String]) -> String {
        var committed = ""
        for part in parts {
            committed = append(committed, part)
        }
        return committed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func append(_ committed: String, _ incoming: String) -> String {
        let next = incoming.trimmingCharacters(in: .whitespacesAndNewlines)
        if next.isEmpty { return committed }
        let base = committed.trimmingCharacters(in: .whitespacesAndNewlines)
        if base.isEmpty { return next }

        let baseWords = words(base)
        let nextWords = words(next)
        guard !baseWords.isEmpty, !nextWords.isEmpty else {
            return base + " " + next
        }

        // Compare words without case or punctuation: the same audio at a window
        // edge often comes back as "silences" in one chunk and "Silences." in the next.
        let baseKeys = baseWords.map(Self.matchKey)
        let nextKeys = nextWords.map(Self.matchKey)
        let maxOverlap = min(12, baseWords.count, nextWords.count)
        var overlap = 0
        if maxOverlap > 0 {
            for k in stride(from: maxOverlap, through: 1, by: -1) {
                if Array(baseKeys.suffix(k)) == Array(nextKeys.prefix(k)) {
                    overlap = k
                    break
                }
            }
        }
        if overlap == nextWords.count {
            return base
        }
        let rest = nextWords.dropFirst(overlap).joined(separator: " ")
        if rest.isEmpty { return base }
        return base + " " + rest
    }

    static func matchKey(_ word: String) -> String {
        String(word.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    }

    public static func words(_ text: String) -> [String] {
        text.split { $0.isWhitespace || $0.isNewline }.map(String.init)
    }
}

/// Split long polish input so the local LLM never sees an hour of text at once.
public enum TextChunker {
    public static func wordChunks(_ text: String, maxWords: Int = 120, overlapWords: Int = 8) -> [String] {
        let tokens = TranscriptStitch.words(text)
        guard !tokens.isEmpty else { return [] }
        let window = max(1, maxWords)
        if tokens.count <= window {
            return [tokens.joined(separator: " ")]
        }
        let overlap = min(max(0, overlapWords), window - 1)
        let step = window - overlap
        var chunks: [String] = []
        var start = 0
        while start < tokens.count {
            let end = min(start + window, tokens.count)
            chunks.append(tokens[start..<end].joined(separator: " "))
            if end >= tokens.count { break }
            start += step
            if start < tokens.count, tokens.count - start < window {
                start = tokens.count - window
            }
        }
        return chunks
    }
}
