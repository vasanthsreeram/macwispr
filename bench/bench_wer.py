#!/usr/bin/env python3
"""Word Error Rate (WER) accuracy bench across ASR engines.

Evaluates official mlx-community checkpoints (and optional FluidAudio CoreML)
on a LibriSpeech test-clean subset with a Whisper-style normalizer.

Usage (from repo root):
  uv run --with 'git+https://github.com/Blaizzy/mlx-audio.git' --with soundfile \\
    python bench/bench_wer.py --max-files 50

  # Faster smoke (10 files):
  uv run --with 'git+https://github.com/Blaizzy/mlx-audio.git' --with soundfile \\
    python bench/bench_wer.py --max-files 10 --models default

  # Include FluidAudio CoreML Parakeet v3 if fluidaudiocli is built:
  python bench/bench_wer.py --max-files 50 --include-fluidaudio
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import tarfile
import time
import urllib.request
from dataclasses import dataclass, field
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATA_DIR = ROOT / "bench" / "data" / "librispeech"
TAR_PATH = DATA_DIR / "test-clean.tar.gz"
EXTRACT_DIR = DATA_DIR / "LibriSpeech" / "test-clean"
LIBRISPEECH_URL = "https://www.openslr.org/resources/12/test-clean.tar.gz"

# Models measured for MacWispr product decisions.
MODELS = [
    {
        "id": "qwen-0.6b-8bit",
        "label": "Qwen3-ASR 0.6B MLX-8bit (app default)",
        "hf": "mlx-community/Qwen3-ASR-0.6B-8bit",
        "backend": "mlx-audio",
        "tier": "default",
    },
    {
        "id": "qwen-1.7b-8bit",
        "label": "Qwen3-ASR 1.7B MLX-8bit",
        "hf": "mlx-community/Qwen3-ASR-1.7B-8bit",
        "backend": "mlx-audio",
        "tier": "full",
    },
    {
        "id": "parakeet-v3",
        "label": "Parakeet TDT 0.6B v3 MLX (multilingual)",
        "hf": "mlx-community/parakeet-tdt-0.6b-v3",
        "backend": "mlx-audio",
        "tier": "default",
    },
    {
        "id": "parakeet-v2",
        "label": "Parakeet TDT 0.6B v2 MLX (English)",
        "hf": "mlx-community/parakeet-tdt-0.6b-v2",
        "backend": "mlx-audio",
        "tier": "default",
    },
    {
        "id": "nemotron-8bit",
        "label": "Nemotron 3.5 streaming 0.6B MLX-8bit",
        "hf": "mlx-community/nemotron-3.5-asr-streaming-0.6b-8bit",
        "backend": "mlx-audio",
        "tier": "default",
    },
    {
        "id": "fluidaudio-v3",
        "label": "Parakeet TDT v3 CoreML (FluidAudio)",
        "hf": None,
        "backend": "fluidaudio",
        "tier": "fluidaudio",
        "version": "v3",
    },
]


# ---------------------------------------------------------------------------
# Text normalization & WER (Whisper-style light normalizer)
# ---------------------------------------------------------------------------

_NUMBER_MAP = {
    "zero": "0", "one": "1", "two": "2", "three": "3", "four": "4",
    "five": "5", "six": "6", "seven": "7", "eight": "8", "nine": "9",
}


def normalize_text(text: str) -> str:
    """Lowercase, drop punctuation, collapse whitespace (LibriSpeech-friendly)."""
    t = text.lower().strip()
    # British/American common ASR variants
    t = t.replace("’", "'").replace("‘", "'").replace("`", "'")
    t = re.sub(r"[^\w\s']", " ", t)
    t = re.sub(r"\s+", " ", t).strip()
    # Drop filler-ish tokens that models sometimes emit as punctuation words
    words = []
    for w in t.split():
        w = w.strip("'")
        if not w:
            continue
        words.append(w)
    return " ".join(words)


def edit_counts(ref: list[str], hyp: list[str]) -> tuple[int, int, int, int]:
    """Levenshtein with counts: substitutions, insertions, deletions, total errors."""
    n, m = len(ref), len(hyp)
    # DP matrix of costs
    d = [[0] * (m + 1) for _ in range(n + 1)]
    for i in range(n + 1):
        d[i][0] = i
    for j in range(m + 1):
        d[0][j] = j
    for i in range(1, n + 1):
        for j in range(1, m + 1):
            if ref[i - 1] == hyp[j - 1]:
                d[i][j] = d[i - 1][j - 1]
            else:
                d[i][j] = 1 + min(d[i - 1][j], d[i][j - 1], d[i - 1][j - 1])

    subs = ins = dels = 0
    i, j = n, m
    while i > 0 or j > 0:
        if i > 0 and j > 0 and ref[i - 1] == hyp[j - 1]:
            i -= 1
            j -= 1
        elif i > 0 and j > 0 and d[i][j] == d[i - 1][j - 1] + 1:
            subs += 1
            i -= 1
            j -= 1
        elif j > 0 and d[i][j] == d[i][j - 1] + 1:
            ins += 1
            j -= 1
        else:
            dels += 1
            i -= 1
    return subs, ins, dels, subs + ins + dels


def wer_pair(reference: str, hypothesis: str) -> dict:
    ref = normalize_text(reference).split()
    hyp = normalize_text(hypothesis).split()
    subs, ins, dels, errors = edit_counts(ref, hyp)
    n = max(len(ref), 1)
    return {
        "wer": errors / n * 100.0,
        "errors": errors,
        "subs": subs,
        "ins": ins,
        "dels": dels,
        "ref_words": len(ref),
        "hyp_words": len(hyp),
    }


# ---------------------------------------------------------------------------
# Dataset
# ---------------------------------------------------------------------------

@dataclass
class Utterance:
    utt_id: str
    path: Path
    text: str
    duration_s: float = 0.0


def ensure_librispeech() -> Path:
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    if EXTRACT_DIR.exists() and any(EXTRACT_DIR.rglob("*.flac")):
        return EXTRACT_DIR

    if not TAR_PATH.exists():
        print(f"Downloading LibriSpeech test-clean (~350 MB) → {TAR_PATH}")
        tmp = TAR_PATH.with_suffix(".partial")
        urllib.request.urlretrieve(LIBRISPEECH_URL, tmp)
        tmp.rename(TAR_PATH)

    print(f"Extracting {TAR_PATH} …")
    with tarfile.open(TAR_PATH, "r:gz") as tf:
        tf.extractall(DATA_DIR, filter='data')

    if not EXTRACT_DIR.exists():
        raise SystemExit(f"Expected {EXTRACT_DIR} after extract")
    n = len(list(EXTRACT_DIR.rglob("*.flac")))
    print(f"  {n} FLAC files ready")
    return EXTRACT_DIR


def load_utterances(max_files: int, min_sec: float, max_sec: float) -> list[Utterance]:
    ensure_librispeech()
    utts: list[Utterance] = []
    for trans_file in sorted(EXTRACT_DIR.rglob("*.trans.txt")):
        chapter_dir = trans_file.parent
        for line in trans_file.read_text().strip().splitlines():
            parts = line.strip().split(" ", 1)
            if len(parts) != 2:
                continue
            utt_id, text = parts
            flac = chapter_dir / f"{utt_id}.flac"
            if not flac.exists():
                continue
            utts.append(Utterance(utt_id=utt_id, path=flac, text=text))
    utts.sort(key=lambda u: u.utt_id)

    # Attach duration and filter short/long extremes (dictation-like window).
    try:
        import soundfile as sf
    except ImportError:
        print("Install soundfile:  uv run --with soundfile …", file=sys.stderr)
        raise

    filtered: list[Utterance] = []
    for u in utts:
        info = sf.info(str(u.path))
        u.duration_s = info.frames / float(info.samplerate)
        if min_sec <= u.duration_s <= max_sec:
            filtered.append(u)
        if max_files > 0 and len(filtered) >= max_files:
            break

    if max_files > 0:
        filtered = filtered[:max_files]
    return filtered


def flac_to_wav16k(src: Path, dst: Path) -> Path:
    """FluidAudio CLI is happier with 16 kHz mono WAV."""
    if dst.exists():
        return dst
    dst.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        [
            "ffmpeg", "-y", "-i", str(src),
            "-ac", "1", "-ar", "16000", str(dst),
        ],
        check=True,
        capture_output=True,
    )
    return dst


# ---------------------------------------------------------------------------
# Engines
# ---------------------------------------------------------------------------

class MlxEngine:
    def __init__(self, hf_id: str):
        from mlx_audio.stt import load

        t0 = time.perf_counter()
        self.model = load(hf_id)
        self.load_s = time.perf_counter() - t0
        self.hf_id = hf_id

    def transcribe(self, path: Path) -> str:
        out = self.model.generate(str(path))
        text = getattr(out, "text", None)
        if text is None:
            text = str(out)
        return text or ""


class FluidAudioEngine:
    def __init__(self, cli: Path, version: str = "v3"):
        self.cli = cli
        self.version = version
        self.load_s = 0.0  # process-per-file; load amortized poorly
        self.wav_cache = DATA_DIR / "wav16k"
        # Warm once
        print(f"  (FluidAudio warm-up {version}…)")
        # Pick any short flac later; skip if none yet

    def transcribe(self, path: Path) -> str:
        wav = self.wav_cache / f"{path.stem}.wav"
        flac_to_wav16k(path, wav)
        proc = subprocess.run(
            [
                str(self.cli),
                "transcribe",
                str(wav),
                "--model-version",
                self.version,
                "--encoder-precision",
                "int8",
            ],
            capture_output=True,
            text=True,
            timeout=600,
        )
        # Last non-empty stdout line is usually the transcript
        lines = [ln.strip() for ln in proc.stdout.splitlines() if ln.strip()]
        # Filter noise lines
        noise = ("E5RT", "error", "warning", "loading", "download")
        clean = [ln for ln in lines if not any(n.lower() in ln.lower() for n in noise)]
        if clean:
            return clean[-1]
        return lines[-1] if lines else ""


# ---------------------------------------------------------------------------
# Evaluation loop
# ---------------------------------------------------------------------------

@dataclass
class EngineResult:
    label: str
    model_id: str
    backend: str
    load_s: float
    utterances: int
    total_audio_s: float
    total_infer_s: float
    aggregate_wer: float
    mean_wer: float
    total_errors: int
    total_ref_words: int
    subs: int
    ins: int
    dels: int
    samples: list[dict] = field(default_factory=list)

    @property
    def rtf(self) -> float:
        if self.total_audio_s <= 0:
            return float("inf")
        return self.total_infer_s / self.total_audio_s


def evaluate(engine, label: str, model_id: str, backend: str, load_s: float,
             utts: list[Utterance], show_examples: int) -> EngineResult:
    total_err = total_ref = 0
    subs = ins = dels = 0
    per_file_wers: list[float] = []
    total_infer = 0.0
    total_audio = 0.0
    samples: list[dict] = []

    for i, u in enumerate(utts, 1):
        t0 = time.perf_counter()
        try:
            hyp = engine.transcribe(u.path)
        except Exception as e:
            print(f"  [{i}/{len(utts)}] {u.utt_id} FAILED: {e}")
            hyp = ""
        elapsed = time.perf_counter() - t0
        total_infer += elapsed
        total_audio += u.duration_s

        m = wer_pair(u.text, hyp)
        total_err += m["errors"]
        total_ref += m["ref_words"]
        subs += m["subs"]
        ins += m["ins"]
        dels += m["dels"]
        per_file_wers.append(m["wer"])

        if len(samples) < show_examples or m["wer"] > 15:
            samples.append({
                "id": u.utt_id,
                "wer": round(m["wer"], 1),
                "ref": u.text,
                "hyp": hyp,
                "sec": round(u.duration_s, 2),
                "lat": round(elapsed, 3),
            })
            # Keep only first show_examples + a few high-error ones
            if len(samples) > show_examples + 5:
                samples = samples[:show_examples] + sorted(
                    samples[show_examples:], key=lambda s: -s["wer"]
                )[:5]

        if i == 1 or i % 10 == 0 or i == len(utts):
            running = total_err / max(total_ref, 1) * 100
            print(
                f"  [{i}/{len(utts)}] running WER {running:.2f}%  "
                f"last {m['wer']:.1f}%  {elapsed:.2f}s / {u.duration_s:.1f}s audio"
            )

    agg = total_err / max(total_ref, 1) * 100
    mean = sum(per_file_wers) / max(len(per_file_wers), 1)
    return EngineResult(
        label=label,
        model_id=model_id,
        backend=backend,
        load_s=load_s,
        utterances=len(utts),
        total_audio_s=total_audio,
        total_infer_s=total_infer,
        aggregate_wer=agg,
        mean_wer=mean,
        total_errors=total_err,
        total_ref_words=total_ref,
        subs=subs,
        ins=ins,
        dels=dels,
        samples=samples[: show_examples + 3],
    )


def select_models(choice: str, include_fluidaudio: bool) -> list[dict]:
    if choice == "all":
        selected = [m for m in MODELS if m["backend"] == "mlx-audio"]
    elif choice == "default":
        selected = [m for m in MODELS if m.get("tier") == "default"]
    elif choice == "qwen":
        selected = [m for m in MODELS if m["id"].startswith("qwen")]
    elif choice == "parakeet":
        selected = [m for m in MODELS if m["id"].startswith("parakeet")]
    elif choice == "nemotron":
        selected = [m for m in MODELS if m["id"].startswith("nemotron")]
    else:
        selected = [m for m in MODELS if m["id"] == choice]
        if not selected:
            raise SystemExit(f"Unknown --models {choice}")

    if include_fluidaudio:
        selected = selected + [m for m in MODELS if m["backend"] == "fluidaudio"]
    return selected


def find_fluidaudio_cli() -> Path | None:
    candidates = [
        Path("/tmp/FluidAudio/.build/release/fluidaudiocli"),
        ROOT / "bench" / "bin" / "fluidaudiocli",
        Path.home() / "FluidAudio" / ".build" / "release" / "fluidaudiocli",
    ]
    for c in candidates:
        if c.is_file() and c.stat().st_mode & 0o111:
            return c
    return None


def print_summary(results: list[EngineResult], out_json: Path | None) -> None:
    print()
    print("═" * 78)
    print("WER SUMMARY — LibriSpeech test-clean subset (lower WER is better)")
    print("═" * 78)
    header = f"{'Model':<46} {'WER%':>7} {'Mean%':>7} {'RTF':>7} {'Err/Wds':>12}"
    print(header)
    print("─" * 78)
    for r in sorted(results, key=lambda x: x.aggregate_wer):
        print(
            f"{r.label:<46} {r.aggregate_wer:6.2f}% {r.mean_wer:6.2f}% "
            f"{r.rtf:7.3f} {r.total_errors:>5}/{r.total_ref_words:<5}"
        )
    print()
    if results:
        best = min(results, key=lambda x: x.aggregate_wer)
        fastest = min(results, key=lambda x: x.rtf)
        print(f"Best accuracy:  {best.label}  ({best.aggregate_wer:.2f}% aggregate WER)")
        print(f"Best speed:     {fastest.label}  (RTF {fastest.rtf:.3f})")
    print()
    print("Notes:")
    print("  • Aggregate WER = total edit distance / total reference words (standard).")
    print("  • Mean WER = average of per-utterance WERs (sensitive to short clips).")
    print("  • Text normalized: lowercase, strip punctuation (LibriSpeech-style).")
    print("  • Subset size is for local iteration; full test-clean is 2620 utts.")

    if out_json:
        payload = {
            "results": [
                {
                    "label": r.label,
                    "model_id": r.model_id,
                    "backend": r.backend,
                    "load_s": r.load_s,
                    "utterances": r.utterances,
                    "total_audio_s": r.total_audio_s,
                    "total_infer_s": r.total_infer_s,
                    "aggregate_wer": r.aggregate_wer,
                    "mean_wer": r.mean_wer,
                    "rtf": r.rtf,
                    "total_errors": r.total_errors,
                    "total_ref_words": r.total_ref_words,
                    "subs": r.subs,
                    "ins": r.ins,
                    "dels": r.dels,
                    "samples": r.samples,
                }
                for r in results
            ]
        }
        out_json.parent.mkdir(parents=True, exist_ok=True)
        out_json.write_text(json.dumps(payload, indent=2))
        print(f"\nWrote {out_json}")


def main() -> int:
    parser = argparse.ArgumentParser(description="ASR WER accuracy bench")
    parser.add_argument("--max-files", type=int, default=50,
                        help="Max LibriSpeech utterances (0 = all ~2620)")
    parser.add_argument("--min-sec", type=float, default=1.0)
    parser.add_argument("--max-sec", type=float, default=30.0)
    parser.add_argument(
        "--models",
        default="default",
        help="default | all | qwen | parakeet | nemotron | <model id>",
    )
    parser.add_argument("--include-fluidaudio", action="store_true",
                        help="Also run FluidAudio CoreML Parakeet v3")
    parser.add_argument("--fluidaudio-cli", type=Path, default=None)
    parser.add_argument("--examples", type=int, default=3,
                        help="Example transcripts to keep per model")
    parser.add_argument(
        "--out",
        type=Path,
        default=ROOT / "bench" / "results" / "wer_latest.json",
    )
    args = parser.parse_args()

    try:
        from mlx_audio.stt import load  # noqa: F401
    except ImportError:
        print(
            "mlx-audio required. Run with:\n"
            "  uv run --with 'git+https://github.com/Blaizzy/mlx-audio.git' "
            "--with soundfile python bench/bench_wer.py …",
            file=sys.stderr,
        )
        return 2

    print("╔══════════════════════════════════════════════════════════════╗")
    print("║          ASR Accuracy Bench — LibriSpeech WER                ║")
    print("╚══════════════════════════════════════════════════════════════╝")

    utts = load_utterances(args.max_files, args.min_sec, args.max_sec)
    audio_s = sum(u.duration_s for u in utts)
    print(f"Utterances: {len(utts)}  (~{audio_s:.0f}s audio, "
          f"{args.min_sec}–{args.max_sec}s each)")
    print()

    selected = select_models(args.models, args.include_fluidaudio)
    results: list[EngineResult] = []

    for spec in selected:
        print(f"▸ {spec['label']}")
        print(f"  backend={spec['backend']}  id={spec.get('hf') or spec['id']}")
        try:
            if spec["backend"] == "mlx-audio":
                engine = MlxEngine(spec["hf"])
                print(f"  loaded in {engine.load_s:.1f}s")
                res = evaluate(
                    engine, spec["label"], spec["hf"], "mlx-audio",
                    engine.load_s, utts, args.examples,
                )
            elif spec["backend"] == "fluidaudio":
                cli = args.fluidaudio_cli or find_fluidaudio_cli()
                if not cli:
                    print("  ✗ fluidaudiocli not found — skip "
                          "(build FluidAudio or pass --fluidaudio-cli)")
                    print()
                    continue
                engine = FluidAudioEngine(cli, version=spec.get("version", "v3"))
                res = evaluate(
                    engine, spec["label"], "FluidAudio/parakeet-tdt-v3",
                    "fluidaudio-coreml", 0.0, utts, args.examples,
                )
            else:
                print(f"  ✗ unknown backend {spec['backend']}")
                continue

            results.append(res)
            print(
                f"  ✓ aggregate WER {res.aggregate_wer:.2f}%  "
                f"mean {res.mean_wer:.2f}%  RTF {res.rtf:.3f}  "
                f"({res.total_errors}/{res.total_ref_words} errors/words)"
            )
            if res.samples:
                s = res.samples[0]
                print(f"  eg ref: {s['ref'][:90]}")
                print(f"     hyp: {s['hyp'][:90]}  (WER {s['wer']}%)")
        except Exception as e:
            print(f"  ✗ skipped: {e}")
        print()

    if not results:
        print("No successful engine runs.", file=sys.stderr)
        return 3

    print_summary(results, args.out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
