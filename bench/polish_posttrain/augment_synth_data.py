#!/usr/bin/env python3
"""Deterministic augmentation of verified synthetic polish examples.

Techniques (no LLM calls — pure transforms on already-validated pairs):
  1. filler injection      — sprinkle "um"/"uh"/"like" into the raw (gold unchanged)
  2. punctuation stripping — degrade raw toward raw ASR output (drop commas/periods, lowercase)
  3. cue paraphrase        — swap the spoken format request for an equivalent phrasing
  4. ordinal swap          — "number two" <-> "number 2" in raws (numbered class)
  5. list splicing         — join two single-list examples into a new multi_list example
                             with headed sections in the gold

Every variant is re-scored with polish_verifier and kept only if it passes for
its tag. Output rows carry source="augment:<technique>". Dedup vs input + output.

Usage:
  python augment_synth_data.py --in data/synth_hard.jsonl --out data/synth_aug.jsonl [--per-technique 150]
"""
import argparse
import json
import random
import re
from pathlib import Path

from polish_verifier import verify

FILLERS = ["um", "uh", "you know", "like", "I mean"]

CUE_SWAPS = {
    "as bullets": ["in bullet points", "bullet it", "as a dashed list"],
    "bullet points": ["bullets please", "as a list with dashes"],
    "numbered": ["as numbered steps", "with numbers"],
    "as a numbered list": ["numbered please", "in a numbered format"],
    "checklist": ["as checkboxes", "as a checkbox list"],
    "as a list": ["as bullet points", "in list form"],
}

ORDINAL_WORDS = {
    "number one": "number 1", "number two": "number 2", "number three": "number 3",
    "number four": "number 4", "number five": "number 5", "number six": "number 6",
}

SPLICE_JOINERS = [
    "and then separately",
    "oh and for the other list",
    "and the second list is",
    "then on a separate note I also need",
]


def norm(s: str) -> str:
    return re.sub(r"[^a-z0-9 ]", "", s.lower()).strip()


def inject_fillers(raw: str, rng: random.Random) -> str:
    words = raw.split()
    if len(words) < 6:
        return raw
    for _ in range(rng.randint(2, 4)):
        pos = rng.randint(1, len(words) - 2)
        words.insert(pos, rng.choice(FILLERS))
    return " ".join(words)


def strip_punct(raw: str) -> str:
    s = re.sub(r"[,.;:]", "", raw)
    return s[0].lower() + s[1:] if s else s


def swap_cue(raw: str, rng: random.Random):
    low = raw.lower()
    for cue, alts in CUE_SWAPS.items():
        if cue in low:
            i = low.index(cue)
            return raw[:i] + rng.choice(alts) + raw[i + len(cue):]
    return None


def swap_ordinals(raw: str) -> str | None:
    out, hit = raw, False
    for w, d in ORDINAL_WORDS.items():
        if w in out.lower():
            out = re.sub(re.escape(w), d, out, flags=re.IGNORECASE)
            hit = True
    return out if hit else None


def heading_from(raw: str) -> str:
    words = [w for w in re.sub(r"[^a-zA-Z ]", "", raw).split() if len(w) > 3][:3]
    return " ".join(words).title() or "List"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--in", dest="inp", default="data/synth_hard.jsonl")
    ap.add_argument("--out", default="data/synth_aug.jsonl")
    ap.add_argument("--per-technique", type=int, default=150)
    ap.add_argument("--seed", type=int, default=11)
    args = ap.parse_args()

    here = Path(__file__).parent
    rng = random.Random(args.seed)
    rows = [json.loads(l) for l in (here / args.inp).read_text().splitlines() if l.strip()]
    seen = {norm(r["raw"]) for r in rows}
    out_path = here / args.out
    kept, stats = [], {}

    def emit(raw, gold, tags, technique):
        key = norm(raw)
        if not key or key in seen:
            return
        if not verify(raw, gold, tags).passed:
            return
        seen.add(key)
        kept.append({"raw": raw, "gold": gold, "tags": tags, "source": f"augment:{technique}"})
        stats[technique] = stats.get(technique, 0) + 1

    pool = rows[:]
    rng.shuffle(pool)

    # 1-4: per-example transforms
    for r in pool:
        raw, gold, tags = r["raw"], r["gold"], r["tags"]
        if stats.get("fillers", 0) < args.per_technique:
            emit(inject_fillers(raw, rng), gold, tags, "fillers")
        if stats.get("punct", 0) < args.per_technique:
            emit(strip_punct(raw), gold, tags, "punct")
        if stats.get("cue", 0) < args.per_technique:
            swapped = swap_cue(raw, rng)
            if swapped:
                emit(swapped, gold, tags, "cue")
        if stats.get("ordinal", 0) < args.per_technique and "format_numbered" in tags:
            swapped = swap_ordinals(raw)
            if swapped:
                emit(swapped, gold, tags, "ordinal")

    # 5: splice two single-list examples into a multi_list example
    singles = [r for r in pool if r["tags"][0] in ("format_bullets", "format_checklist")
               and "\n\n" not in r["gold"]]
    rng.shuffle(singles)
    for a, b in zip(singles[0::2], singles[1::2]):
        if stats.get("splice", 0) >= args.per_technique:
            break
        joiner = rng.choice(SPLICE_JOINERS)
        raw = f"{a['raw'].rstrip('. ')} {joiner} {b['raw'][0].lower()}{b['raw'][1:]}"
        gold = (f"{heading_from(a['raw'])}:\n{a['gold']}\n\n"
                f"{heading_from(b['raw'])}:\n{b['gold']}")
        emit(raw, gold, ["multi_list"], "splice")

    with out_path.open("w") as f:
        for r in kept:
            f.write(json.dumps(r) + "\n")
    print("AUGMENT DONE", json.dumps({"kept": len(kept), "by_technique": stats}))


if __name__ == "__main__":
    main()
