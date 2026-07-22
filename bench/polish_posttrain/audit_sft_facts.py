#!/usr/bin/env python3
"""Audit SFT golds for fact-retention practices.

For each train example, extract 'hard facts' from the raw (digits, spelled-out
numbers, capitalized-name-like words, negations, times) and check whether the
gold keeps them (digit forms accepted for spelled-out numbers). Reports the
fraction of examples whose gold drops at least one fact, with samples.
"""
from __future__ import annotations

import json
import re
import sys
from collections import Counter
from pathlib import Path

WORD_NUM = {
    "one": "1", "two": "2", "three": "3", "four": "4", "five": "5", "six": "6",
    "seven": "7", "eight": "8", "nine": "9", "ten": "10", "eleven": "11",
    "twelve": "12", "fifteen": "15", "twenty": "20", "thirty": "30",
    "forty": "40", "fifty": "50", "sixty": "60", "seventy": "70",
    "eighty": "80", "ninety": "90", "hundred": "00", "thousand": "000",
    "dozen": "12",
}
NEG_RE = re.compile(r"\b(not|don't|do not|doesn't|never|no longer|except|excluding|but not)\b", re.I)


def split_example(text: str):
    m = re.search(r"### Input:\n(.*?)\n\n### Output:\n(.*)", text, re.S)
    return (m.group(1), m.group(2)) if m else (None, None)


def facts(raw: str):
    out = []
    for d in re.findall(r"\d+(?:[.:]\d+)?", raw):
        out.append(("digit", d))
    for w in re.findall(r"[a-z']+", raw.lower()):
        if w in WORD_NUM:
            out.append(("wordnum", w))
    for m in NEG_RE.finditer(raw):
        out.append(("negation", m.group(0).lower()))
    return out


def kept(fact, gold: str) -> bool:
    kind, val = fact
    g = gold.lower()
    if kind == "digit":
        return val in gold
    if kind == "wordnum":
        return val in g or WORD_NUM[val] in gold
    if kind == "negation":
        return bool(NEG_RE.search(gold))
    return True


def main():
    path = Path(sys.argv[1])
    rows = [json.loads(l) for l in path.read_text().splitlines() if l.strip()]
    n_with_facts = n_dropped = 0
    drop_kinds = Counter()
    samples = []
    fact_total = fact_kept = 0
    for r in rows:
        raw, gold = split_example(r["text"])
        if raw is None:
            continue
        fs = facts(raw)
        if not fs:
            continue
        n_with_facts += 1
        missing = [f for f in fs if not kept(f, gold)]
        fact_total += len(fs)
        fact_kept += len(fs) - len(missing)
        if missing:
            n_dropped += 1
            for k, v in missing:
                drop_kinds[k] += 1
            if len(samples) < 8:
                samples.append((missing[:4], raw[:130], gold[:130]))
    print(f"examples with hard facts: {n_with_facts}/{len(rows)}")
    print(f"examples where gold DROPS >=1 fact: {n_dropped} ({n_dropped/max(1,n_with_facts):.1%})")
    print(f"gold fact retention: {fact_kept}/{fact_total} ({fact_kept/max(1,fact_total):.1%})")
    print("dropped by kind:", dict(drop_kinds))
    print("\n--- samples of drops ---")
    for miss, raw, gold in samples:
        print(f"missing {miss}\n  RAW : {raw}\n  GOLD: {gold}\n")


if __name__ == "__main__":
    main()
