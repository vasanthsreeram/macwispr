"""Tier-1 reference-based similarity reward: embedding cosine + ROUGE-L.

Scores a candidate polish against a reference polish (Flash-Lite distill
output). Combined score = 0.6 * embedding_cosine + 0.4 * rouge_l_f1 —
the cheap stable baseline for reference-based RL rewards.

Bands (calibrate with --calibrate before trusting at scale):
  combined >= HI  -> semantically equivalent to reference (accept)
  combined <= LO  -> meaning drifted / over-simplified (reject)
  else            -> ambiguous, escalate to LLM judge (Tier 2)

Embedding model runs locally (bge-small-en-v1.5, ~130MB). Lazy-loaded so
importing this module stays cheap for rule-only callers.
"""
from __future__ import annotations

import re

HI = 0.90
LO = 0.70

_model = None


def _embedder():
    global _model
    if _model is None:
        from sentence_transformers import SentenceTransformer
        _model = SentenceTransformer("BAAI/bge-small-en-v1.5")
    return _model


def _tokens(text: str) -> list[str]:
    return re.findall(r"[a-z0-9]+", text.lower())


def rouge_l_f1(candidate: str, reference: str) -> float:
    """ROUGE-L F1 via LCS over word tokens. Pure Python, no deps."""
    a, b = _tokens(candidate), _tokens(reference)
    if not a or not b:
        return 0.0
    # O(len(a)*len(b)) DP with two rows
    prev = [0] * (len(b) + 1)
    for x in a:
        cur = [0]
        for j, y in enumerate(b, 1):
            cur.append(prev[j - 1] + 1 if x == y else max(prev[j], cur[-1]))
        prev = cur
    lcs = prev[-1]
    p, r = lcs / len(a), lcs / len(b)
    return 0.0 if p + r == 0 else 2 * p * r / (p + r)


def embed_cosine(candidate: str, reference: str) -> float:
    embs = _embedder().encode([candidate, reference], normalize_embeddings=True)
    return float(embs[0] @ embs[1])


def embed_cosine_batch(pairs: list[tuple[str, str]]) -> list[float]:
    """Batched version — one encode call for all candidates + references."""
    texts = [t for pair in pairs for t in pair]
    embs = _embedder().encode(texts, normalize_embeddings=True, batch_size=64)
    return [float(embs[2 * i] @ embs[2 * i + 1]) for i in range(len(pairs))]


def similarity(candidate: str, reference: str) -> dict:
    cos = embed_cosine(candidate, reference)
    rouge = rouge_l_f1(candidate, reference)
    combined = 0.6 * cos + 0.4 * rouge
    band = "accept" if combined >= HI else "reject" if combined <= LO else "ambiguous"
    return {"cosine": cos, "rouge_l": rouge, "combined": combined, "band": band}


if __name__ == "__main__":
    import argparse
    import json
    from pathlib import Path

    ap = argparse.ArgumentParser(description="Score candidates vs references")
    ap.add_argument("--pairs", help="jsonl with {candidate, reference} per line")
    ap.add_argument("--calibrate", action="store_true",
                    help="print band distribution instead of per-line scores")
    args = ap.parse_args()

    rows = [json.loads(l) for l in Path(args.pairs).read_text().splitlines() if l.strip()]
    cosines = embed_cosine_batch([(r["candidate"], r["reference"]) for r in rows])
    bands = {"accept": 0, "ambiguous": 0, "reject": 0}
    for r, cos in zip(rows, cosines):
        rouge = rouge_l_f1(r["candidate"], r["reference"])
        combined = 0.6 * cos + 0.4 * rouge
        band = "accept" if combined >= HI else "reject" if combined <= LO else "ambiguous"
        bands[band] += 1
        if not args.calibrate:
            print(json.dumps({**r, "cosine": round(cos, 4),
                              "rouge_l": round(rouge, 4),
                              "combined": round(combined, 4), "band": band}))
    if args.calibrate:
        n = len(rows)
        for b, c in bands.items():
            print(f"{b:10s} {c:6d}  ({c / n:.1%})")
