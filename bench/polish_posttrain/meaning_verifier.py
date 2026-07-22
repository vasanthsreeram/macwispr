#!/usr/bin/env python3
"""Meaning-preservation verifier for polish outputs.

Each case declares `must` facts — details the polished output must keep —
and optional `forbid` patterns (meaning flips, e.g. a dropped negation).
A fact is a list of alternative regexes (case-insensitive); any one
matching counts as kept, so reasonable rephrasing is allowed.

score = fraction of facts kept, minus 0.5 per forbid hit (floor -1).
passed = all facts kept and no forbid hits.

Usable as an RL reward alongside polish_verifier.verify.
"""
from __future__ import annotations

import unicodedata

import re
from dataclasses import dataclass, field


@dataclass
class MeaningVerdict:
    score: float
    passed: bool
    kept: int = 0
    total: int = 0
    missing: list[str] = field(default_factory=list)
    flips: list[str] = field(default_factory=list)


_UNICODE_MAP = str.maketrans({
    " ": " ", " ": " ", " ": " ", " ": " ",  # nbsp/narrow spaces
    "‐": "-", "‑": "-", "‒": "-", "–": "-", "—": "-",
    "‘": "'", "’": "'", "“": '"', "”": '"',
})


def _strip_accents(text: str) -> str:
    return "".join(c for c in unicodedata.normalize("NFD", text)
                   if unicodedata.category(c) != "Mn")


def _normalize(text: str) -> str:
    # Typographic output (narrow spaces, curly quotes, U+2011 hyphens, accents)
    # must not defeat ASCII patterns; "6 p.m."→"6pm", "6:00 pm"→"6pm".
    text = _strip_accents(text.translate(_UNICODE_MAP))
    text = re.sub(r"\b([ap])\.m\.", r"\1m", text, flags=re.I)
    text = re.sub(r"\b(\d{1,2}):00\s*([ap]m)\b", r"\1\2", text, flags=re.I)
    return text


def verify_meaning(out: str, must: list[list[str]], forbid: list[str] | None = None) -> MeaningVerdict:
    out = _normalize(out)
    missing = []
    for alternatives in must:
        if not any(re.search(a, out, re.I) for a in alternatives):
            missing.append(alternatives[0])
    flips = [f for f in (forbid or []) if re.search(f, out, re.I)]
    total = len(must)
    kept = total - len(missing)
    score = (kept / total if total else 1.0) - 0.5 * len(flips)
    return MeaningVerdict(
        score=max(-1.0, score),
        passed=not missing and not flips,
        kept=kept,
        total=total,
        missing=missing,
        flips=flips,
    )
