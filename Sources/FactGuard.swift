import Foundation

/// Inference-time fact-retention guard for polished dictation.
///
/// The polish model is a 0.8B 4-bit sampler — it occasionally drops or corrupts
/// hard facts (e.g. `$750` → `$7,500`, a dropped "not"). No training run makes a
/// model of this size *guaranteed* faithful, but at inference we hold both the
/// raw transcript and the polish, so we can cheaply verify and fall back.
///
/// This is the Swift counterpart of `bench/polish_posttrain/fact_heuristic.py`,
/// deliberately restricted to the checks that are **false-positive-safe** without
/// the full spoken-number parser: literal digits present in the raw must survive,
/// and a meaningful negation must not silently vanish. We do NOT flag "invented"
/// numbers here — spoken-number expansion ("twelve thousand" → "12,000")
/// legitimately introduces digits the raw lacks, and flagging those would reject
/// correct polishes (the exact brittleness the v5 reward cascade was built to fix).
///
/// A `false` result means "this polish lost a fact I can prove was in the raw" —
/// the caller should retry or fall back to the raw text.
enum FactGuard {
    /// Digit runs written literally in the source, e.g. "302", "750", "12".
    /// Spoken numbers ("twelve thousand") are intentionally not parsed here.
    private static func literalDigitRuns(_ text: String) -> [String] {
        var runs: [String] = []
        var current = ""
        for ch in text {
            if ch.isNumber {
                current.append(ch)
            } else if !current.isEmpty {
                runs.append(current)
                current = ""
            }
        }
        if !current.isEmpty { runs.append(current) }
        return runs
    }

    /// Meaningful negations. Idioms ("don't forget", "no problem") are filler a
    /// good polish may drop, so they must not count — mirrors `NEG_IDIOM_RE`.
    private static let negationWords = [
        "not", "don't", "dont", "doesn't", "doesnt", "never",
        "no longer", "except", "excluding", "but not",
    ]
    private static let negationIdioms = [
        "don't forget", "dont forget", "do not forget", "don't worry",
        "dont worry", "don't hesitate", "not sure", "no problem", "no worries",
    ]

    private static func strippedForNegation(_ text: String) -> String {
        var s = text.lowercased()
        for idiom in negationIdioms { s = s.replacingOccurrences(of: idiom, with: " ") }
        return s
    }

    private static func hasMeaningfulNegation(_ text: String) -> Bool {
        let s = strippedForNegation(text)
        return negationWords.contains { word in
            // word-boundary-ish: surround with non-alphanumerics
            let padded = " \(s) "
            return padded.contains(" \(word) ") || padded.contains(" \(word),")
                || padded.contains(" \(word).") || padded.contains(" \(word)!")
        }
    }

    /// Returns the digits string with grouping separators removed for comparison,
    /// so "7,200" in the output still matches raw "7200" and vice versa.
    private static func digitsOnly(_ text: String) -> String {
        text.filter { $0.isNumber }
    }

    /// True when `output` preserves the facts we can verify from `raw`.
    static func preservesFacts(raw: String, output: String) -> Bool {
        let outDigits = digitsOnly(output)
        // Every literal digit run in the raw must appear (as a contiguous digit
        // substring) somewhere in the output's digits. This catches drops
        // ("302" gone) and corruptions ("750" → "7500", since "750" ⊄ "7500"
        // only when the run differs — see note below).
        // A dropped number ("302" gone entirely) is caught reliably and without
        // false positives. We use substring containment rather than exact-run
        // matching on purpose: exact-run would flag legitimate reformatting like
        // "555 1234" → "5551234". The trade-off is that pure corruptions where
        // the digits still appear as a substring ("750" → "7500") slip past this
        // net — those are the v5 training round's direct target, not the guard's.
        for run in literalDigitRuns(raw) {
            if !outDigits.contains(run) { return false }
        }
        // Negation must survive if the raw carried a meaningful one.
        if hasMeaningfulNegation(raw), !hasMeaningfulNegation(output) {
            return false
        }
        return true
    }
}
