#!/usr/bin/env python3
"""Latency bench for official mlx-community ASR models via mlx-audio.

Covers Nemotron 3.5 streaming (the small ~0.6B cache-aware model FluidVoice also
ships as CoreML) and optional Parakeet TDT MLX for apples-to-apples backend compare.

Usage (from repo root):
  uv run --with 'git+https://github.com/Blaizzy/mlx-audio.git' \\
    python bench/bench_mlx_audio.py [clip.wav]

  # or after: pip install 'git+https://github.com/Blaizzy/mlx-audio.git'
  python3 bench/bench_mlx_audio.py bench/clips/speech_12s_16k.wav
"""

from __future__ import annotations

import argparse
import sys
import time
from pathlib import Path


# Official mlx-community checkpoints (Nemotron needs mlx-audio main, not 0.4.3).
# Parakeet: v3 = multilingual (25 EU langs, FluidVoice default batch ASR);
#           v2 = English-only (slightly better EN recall).
MODELS = [
    {
        "label": "Nemotron 3.5 ASR streaming 0.6B MLX-8bit",
        "id": "mlx-community/nemotron-3.5-asr-streaming-0.6b-8bit",
        "kind": "nemotron",
        "tier": "default",
    },
    {
        "label": "Nemotron 3.5 ASR streaming 0.6B MLX-bf16",
        "id": "mlx-community/nemotron-3.5-asr-streaming-0.6b",
        "kind": "nemotron",
        "tier": "full",
    },
    {
        "label": "Parakeet TDT 0.6B v3 MLX (multilingual)",
        "id": "mlx-community/parakeet-tdt-0.6b-v3",
        "kind": "parakeet",
        "tier": "default",  # primary Parakeet — same generation FluidVoice uses
    },
    {
        "label": "Parakeet TDT 0.6B v2 MLX (English-only)",
        "id": "mlx-community/parakeet-tdt-0.6b-v2",
        "kind": "parakeet",
        "tier": "full",
    },
]


def audio_duration_seconds(path: Path) -> float:
    import wave

    with wave.open(str(path), "rb") as w:
        return w.getnframes() / float(w.getframerate())


def preview(text: str, limit: int = 100) -> str:
    t = " ".join((text or "").split())
    if not t:
        return "(empty)"
    return t if len(t) <= limit else t[:limit] + "…"


def run_model(model_id: str, audio: Path, runs: int = 3) -> tuple[float, float, list[float], str]:
    from mlx_audio.stt import load

    t0 = time.perf_counter()
    model = load(model_id)
    load_s = time.perf_counter() - t0

    # Warmup (compile / cache)
    t0 = time.perf_counter()
    _ = model.generate(str(audio))
    warmup_s = time.perf_counter() - t0

    times: list[float] = []
    last_text = ""
    for i in range(runs):
        t0 = time.perf_counter()
        out = model.generate(str(audio))
        elapsed = time.perf_counter() - t0
        times.append(elapsed)
        last_text = getattr(out, "text", None) or str(out)
        print(f"  run {i + 1}: {elapsed:.3f}s")

    return load_s, warmup_s, times, last_text


def main() -> int:
    parser = argparse.ArgumentParser(description="Bench mlx-community ASR models")
    parser.add_argument(
        "clip",
        nargs="?",
        default="bench/clips/speech_12s_16k.wav",
        help="16 kHz mono WAV (or any format mlx-audio accepts)",
    )
    parser.add_argument(
        "--models",
        choices=["default", "all", "nemotron", "parakeet", "parakeet-v3", "nemotron-8bit"],
        default="default",
        help=(
            "Subset: default = Nemotron-8bit + Parakeet v3; "
            "parakeet = v3+v2; parakeet-v3 = v3 only; all = everything"
        ),
    )
    parser.add_argument("--runs", type=int, default=3)
    args = parser.parse_args()

    clip = Path(args.clip)
    if not clip.is_file():
        print(f"Missing audio: {clip}", file=sys.stderr)
        return 1

    try:
        from mlx_audio.stt import load  # noqa: F401
    except ImportError:
        print(
            "mlx-audio not installed (or too old for Nemotron).\n"
            "Install from GitHub main:\n"
            "  uv run --with 'git+https://github.com/Blaizzy/mlx-audio.git' "
            f"python {Path(__file__).name} ...\n"
            "  # or: pip install 'git+https://github.com/Blaizzy/mlx-audio.git'",
            file=sys.stderr,
        )
        return 2

    if args.models == "all":
        selected = MODELS
    elif args.models == "default":
        selected = [m for m in MODELS if m.get("tier") == "default"]
    elif args.models == "nemotron":
        selected = [m for m in MODELS if m["kind"] == "nemotron"]
    elif args.models == "nemotron-8bit":
        selected = [m for m in MODELS if m["id"].endswith("-8bit")]
    elif args.models == "parakeet-v3":
        selected = [m for m in MODELS if "parakeet-tdt-0.6b-v3" in m["id"]]
    else:
        selected = [m for m in MODELS if m["kind"] == "parakeet"]

    duration = audio_duration_seconds(clip)
    print("╔══════════════════════════════════════════════════════════════╗")
    print("║     mlx-audio Latency Bench — Nemotron / Parakeet (MLX)      ║")
    print("╚══════════════════════════════════════════════════════════════╝")
    print(f"Clip: {clip} ({duration:.2f}s)")
    print(f"Method: load once → warmup generate → {args.runs} timed runs → best")
    print()

    results: list[tuple[str, float, float, float, str]] = []

    for spec in selected:
        print(f"▸ {spec['label']}")
        print(f"  model: {spec['id']}")
        try:
            load_s, warmup_s, times, text = run_model(spec["id"], clip, runs=args.runs)
            best = min(times)
            rtf = best / duration if duration > 0 else float("inf")
            results.append((spec["label"], best, rtf, load_s, text))
            print(
                f"  ✓ best: {best:.3f}s  RTF {rtf:.3f}  load: {load_s:.1f}s  warmup: {warmup_s:.1f}s"
            )
            print(f"  text: {preview(text)}")
        except Exception as e:
            print(f"  ✗ skipped: {e}")
        print()

    if not results:
        print("No successful runs.", file=sys.stderr)
        return 3

    results.sort(key=lambda r: r[1])
    max_lat = max(r[1] for r in results)
    print("═══════════════════════════════════════════════════════════════")
    print(f"SUMMARY — inference latency for {duration:.1f}s audio")
    print("═══════════════════════════════════════════════════════════════")
    print(f"{'Model':<44} {'Latency':>8} {'RTF':>8} {'Load':>8}")
    print("─" * 72)
    for label, best, rtf, load_s, _ in results:
        bar_n = max(1, int((best / max_lat) * 16))
        marker = " ← fastest" if best == results[0][1] else ""
        print(f"{label:<44} {best:6.2f}s {rtf:8.3f} {load_s:6.1f}s  {'█' * bar_n}{marker}")

    winner = results[0]
    print()
    print(
        f"Winner: {winner[0]} ({winner[1]:.2f}s for {duration:.1f}s audio, "
        f"{duration / winner[1]:.1f}× realtime)"
    )
    print()
    print("Compare to Swift/CoreML engines with:  ./bench.sh " + str(clip))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
