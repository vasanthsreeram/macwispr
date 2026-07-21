#!/usr/bin/env python3
"""Shared outcome verifier for polish outputs.

One rule set used everywhere: offline eval metric AND RL reward
(DPO pair ranking / GRPO reward). Returns (score, feedback).

Score is in [-1, 1]. Feedback is a short text usable for
sequential-revision training prompts.
"""
from __future__ import annotations

import re
from dataclasses import dataclass, field

BULLET_RE = re.compile(r"^\s*-\s+(?!\[)", re.M)
CHECKBOX_RE = re.compile(r"^\s*-\s+\[[ xX]\]", re.M)
NUMBERED_RE = re.compile(r"^\s*\d+[.)]\s+", re.M)
HEADING_RE = re.compile(r"^(#{1,4}\s+\S|[^\n]{1,60}:\s*$|\*\*[^\n]+\*\*\s*$)", re.M)
FILLER_RE = re.compile(
    r"\b(no wait|scratch that|actually,? (?:no|wait)|um+|uh+|you know what)\b", re.I
)
# Leak = model answered the dictation instead of polishing it.
LEAK_RE = re.compile(
    r"^(sure|certainly|here(?:'s| is)|as an ai|i(?:'d| would) (?:be happy|suggest)|great question)\b",
    re.I,
)

STOPWORDS = set(
    "the a an and or but to of in on for with is are was were be i you it this that".split()
) | set(
    # Format-instruction words: legitimately absent from a good output.
    "bullet bullets bulleted list listed number numbered checklist checkbox "
    "checkboxes make please those them item items rank ranked order write".split()
)


def _content_words(text: str) -> set[str]:
    return {
        w.lower()
        for w in re.findall(r"[A-Za-z][A-Za-z'\-]+", text)
        if w.lower() not in STOPWORDS and len(w) > 2
    }


def _list_blocks(text: str) -> int:
    """Count separate list blocks (list runs separated by non-list lines)."""
    blocks, in_block = 0, False
    for line in text.splitlines():
        is_item = bool(
            BULLET_RE.match(line) or CHECKBOX_RE.match(line) or NUMBERED_RE.match(line)
        )
        if is_item and not in_block:
            blocks += 1
        in_block = is_item
    return blocks


@dataclass
class Verdict:
    score: float
    passed: bool
    feedback: list[str] = field(default_factory=list)


def verify(raw: str, out: str, tags: list[str]) -> Verdict:
    """Score a polished output against intent tags.

    tags: subset of {multi_list, mixed_styles, format_numbered, format_bullets,
    format_checklist, preserve_prose, preserve_question, email, light}
    """
    fb: list[str] = []
    score = 0.0

    has_bullets = bool(BULLET_RE.search(out))
    has_numbers = bool(NUMBERED_RE.search(out))
    has_checks = bool(CHECKBOX_RE.search(out))
    blocks = _list_blocks(out)

    # Hard failure: answer leak.
    if LEAK_RE.match(out.strip()):
        return Verdict(-1.0, False, ["answer_leak: output answers instead of polishing"])

    # Residual filler / course-correction not cleaned.
    if FILLER_RE.search(out):
        score -= 0.4
        fb.append("residual filler/course-correction left in output")

    if "multi_list" in tags:
        if blocks >= 2 and HEADING_RE.search(out):
            score += 1.0
        elif blocks >= 2:
            score += 0.5
            fb.append("has >=2 list blocks but missing headings/titles")
        else:
            score -= 1.0
            fb.append(f"expected >=2 headed list blocks, got {blocks} (flattened)")

    if "mixed_styles" in tags:
        if has_numbers and (has_bullets or has_checks):
            score += 1.0
        else:
            score -= 1.0
            fb.append("expected numbered AND bullet/checkbox styles together")

    if "format_numbered" in tags:
        score += 1.0 if has_numbers else -1.0
        if not has_numbers:
            fb.append("expected numbered list")
        if has_numbers and has_bullets:
            score -= 0.3
            fb.append("stray bullets alongside requested numbered list")

    if "format_bullets" in tags:
        score += 1.0 if has_bullets else -1.0
        if not has_bullets:
            fb.append("expected bullet list")

    if "format_checklist" in tags:
        score += 1.0 if has_checks else -1.0
        if not has_checks:
            fb.append("expected - [ ] checklist items")

    if "preserve_prose" in tags or "light" in tags:
        if blocks == 0:
            score += 1.0
        else:
            score -= 1.0
            fb.append("over-listed: prose input should stay prose")

    if "preserve_question" in tags:
        if "?" in out and not LEAK_RE.match(out.strip()):
            score += 1.0
        else:
            score -= 1.0
            fb.append("question was answered or lost its question mark")

    if "email" in tags:
        ok = bool(re.search(r"^(hi|hello|hey|dear)\b", out, re.I | re.M)) and bool(
            re.search(r"(thanks|regards|best|cheers)", out, re.I)
        )
        score += 0.5 if ok else -0.5
        if not ok:
            fb.append("email missing greeting and/or sign-off")

    # Fidelity: content-word coverage of the raw.
    raw_words = _content_words(raw)
    if raw_words:
        cov = len(raw_words & _content_words(out)) / len(raw_words)
        # Course-corrections legitimately drop words; only punish real loss.
        if cov < 0.55:
            score -= 0.8
            fb.append(f"low content coverage ({cov:.0%}) — dropped items?")
        else:
            score += 0.3 * cov

    # Normalize roughly to [-1, 1].
    n_terms = max(1, len(tags)) + 1
    norm = max(-1.0, min(1.0, score / n_terms * 1.5))
    return Verdict(norm, norm > 0.25 and not fb, fb)


if __name__ == "__main__":
    import json
    import sys

    raw, out = sys.argv[1], sys.argv[2]
    tags = sys.argv[3].split(",") if len(sys.argv) > 3 else []
    v = verify(raw, out, tags)
    print(json.dumps({"score": v.score, "passed": v.passed, "feedback": v.feedback}))
