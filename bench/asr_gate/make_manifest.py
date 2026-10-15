#!/usr/bin/env python3
"""Regenerate bench/asr_gate/manifest.json (stdlib only, deterministic).

The manifest is committed. Re-run only to change the test set, and re-baseline
after you do: results from different manifests are not comparable.

  python3 bench/asr_gate/make_manifest.py
"""

from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
LIBRI = ROOT / "bench" / "data" / "librispeech" / "LibriSpeech" / "test-clean"
OUT = Path(__file__).with_name("manifest.json")

# Dictation-length English: ~3-20 s (word count is a stable proxy for length).
DICTATION_COUNT = 100
DICTATION_WORDS = (8, 55)
# Near the 28 s window edge: exercises padding and the window boundary.
LONG_COUNT = 8
LONG_MIN_WORDS = 70

# Spoken by macOS `say` (prepare.sh). Fixed text = exact references.
TTS = [
    ("fr", "Eddy (French (France))", [
        "Bonjour, je voudrais réserver une table pour deux personnes ce soir.",
        "La réunion de demain est déplacée à quinze heures dans la grande salle.",
        "Pouvez-vous m'envoyer le rapport avant la fin de la semaine?",
    ]),
    ("de", "Eddy (German (Germany))", [
        "Guten Morgen, ich möchte einen Termin für nächste Woche vereinbaren.",
        "Das Projekt ist fast fertig, aber wir brauchen noch zwei Tage.",
        "Bitte schicken Sie mir die Unterlagen per E-Mail.",
    ]),
    ("es", "Eddy (Spanish (Spain))", [
        "Hola, necesito cambiar la fecha de mi vuelo a Madrid.",
        "El equipo terminó el informe y lo enviará mañana por la mañana.",
        "¿Puedes recordarme la contraseña de la red de la oficina?",
    ]),
    ("it", "Eddy (Italian (Italy))", [
        "Buongiorno, vorrei prenotare una camera per tre notti.",
        "La presentazione è pronta e la condivido con tutti dopo pranzo.",
        "Ricordati di chiamare il cliente prima delle cinque.",
    ]),
    ("pt", "Eddy (Portuguese (Brazil))", [
        "Bom dia, gostaria de agendar uma reunião para quinta-feira.",
        "O relatório está quase pronto, só falta revisar os números.",
        "Você pode me mandar o endereço do novo escritório?",
    ]),
]


def load_libri() -> list[tuple[str, str]]:
    if not LIBRI.exists():
        raise SystemExit(f"LibriSpeech test-clean not found at {LIBRI}. Run bench/asr_gate/prepare.sh first.")
    rows: list[tuple[str, str]] = []
    for trans in sorted(LIBRI.rglob("*.trans.txt")):
        for line in trans.read_text().splitlines():
            utt, _, text = line.strip().partition(" ")
            if text:
                rows.append((utt, text))
    rows.sort()
    return rows


def spread(rows: list, n: int) -> list:
    if len(rows) <= n:
        return rows
    step = len(rows) / n
    return [rows[int(i * step)] for i in range(n)]


def main() -> None:
    rows = load_libri()
    dictation = [r for r in rows if DICTATION_WORDS[0] <= len(r[1].split()) <= DICTATION_WORDS[1]]
    long_rows = [r for r in rows if len(r[1].split()) >= LONG_MIN_WORDS]
    picked = spread(dictation, DICTATION_COUNT)
    long_picked = spread(long_rows, LONG_COUNT)

    items: list[dict] = []
    for utt, text in picked:
        items.append({"id": f"ls-{utt}", "set": "english", "librispeech": [utt], "text": text})
    for utt, text in long_picked:
        items.append({"id": f"ls-long-{utt}", "set": "english_long", "librispeech": [utt], "text": text})

    # Long-form: consecutive utterances joined, exercising 28 s windows + stitching.
    used = {r[0] for r in picked}
    pool = [r for r in dictation if r[0] not in used]
    for target_words, label in ((170, "60s"), (500, "3min")):
        chain, words = [], 0
        for utt, text in pool:
            chain.append((utt, text))
            words += len(text.split())
            if words >= target_words:
                break
        pool = pool[len(chain):]
        items.append({
            "id": f"longform-{label}",
            "set": "longform",
            "librispeech": [u for u, _ in chain],
            "text": " ".join(t for _, t in chain),
        })

    for lang, voice, sentences in TTS:
        for i, sentence in enumerate(sentences):
            items.append({
                "id": f"tts-{lang}-{i}",
                "set": "multilingual",
                "tts": {"voice": voice, "file": f"tts-{lang}-{i}.wav"},
                "text": sentence,
            })

    items.append({"id": "silence-3s", "set": "silence", "silence_seconds": 3.0, "text": ""})

    OUT.write_text(json.dumps({"version": 1, "items": items}, indent=1, ensure_ascii=False) + "\n")
    counts: dict[str, int] = {}
    for it in items:
        counts[it["set"]] = counts.get(it["set"], 0) + 1
    print(f"wrote {OUT.relative_to(ROOT)}: {counts}")


if __name__ == "__main__":
    main()
