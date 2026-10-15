#!/usr/bin/env bash
# DPO v5: tiered-cascade pairs (rules + similarity + Flash-Lite judge) from
# v4-dpo100. ~3.8k pairs (vs v4's 54). Light run (v4 lesson: heavy DPO crashes
# structure 80%->55%). Then fuse, 4-bit quantize, eval BOTH suites BOTH precisions.
set -euo pipefail

BASE="${HOME}/.cache/macwispr-minicpm-bench"
BENCH="${HOME}/macwispr-polish-bench"
PP="${BASE}/polish_posttrain"
# shellcheck disable=SC1091
source "${BASE}/.venv312/bin/activate"
export PYTHONPATH="${PP}${PYTHONPATH:+:$PYTHONPATH}"
cd "$PP"

# Start from the current ship candidate so v5 builds on its gains.
BASEMODEL="${BENCH}/fused/qwen35-08b-polish-v4-dpo100"
ADAPTER="${BENCH}/adapters/qwen35-08b-polish-v5-dpo"
FUSED="${BENCH}/fused/qwen35-08b-polish-v5-dpo"
QUANT="${BENCH}/fused/qwen35-08b-polish-v5-dpo-4bit"
RESULTS="${BENCH}/results"

echo "=== DPO v5 start $(date -Iseconds) ==="

# Split pairs (5% valid).
python - <<'PY'
import json, random
from pathlib import Path
pp = Path.home() / ".cache/macwispr-minicpm-bench/polish_posttrain"
rows = [json.loads(l) for l in (pp / "data/dpo_pairs_v5.jsonl").read_text().splitlines() if l.strip()]
rng = random.Random(5); rng.shuffle(rows)
n_val = max(20, len(rows) // 20)
out = pp / "dpo_v5_data"; out.mkdir(exist_ok=True)
(out / "valid.jsonl").write_text("\n".join(json.dumps(r) for r in rows[:n_val]) + "\n")
(out / "train.jsonl").write_text("\n".join(json.dumps(r) for r in rows[n_val:]) + "\n")
print(f"dpo_v5 data: train={len(rows)-n_val} valid={n_val}")
PY

# Light DPO. save-every 50 so an Abort-trap-6 (known mlx_lm_lora flake) resumes
# cheaply; checkpoints also let us pick the pre-structure-regression iter.
rm -rf "$ADAPTER"
mlx_lm_lora.train \
  --model "$BASEMODEL" \
  --train \
  --train-mode dpo \
  --train-type lora \
  --data "${PP}/dpo_v5_data" \
  --batch-size 2 \
  --iters 150 \
  --learning-rate 5e-6 \
  --beta 0.1 \
  --max-seq-length 1024 \
  --adapter-path "$ADAPTER" \
  --save-every 25 \
  --steps-per-eval 25 \
  --steps-per-report 20 \
  --seed 42

rm -rf "$FUSED"
mlx_lm.fuse --model "$BASEMODEL" --adapter-path "$ADAPTER" --save-path "$FUSED"
rm -rf "$QUANT"
mlx_lm.convert --hf-path "$FUSED" --mlx-path "$QUANT" -q --q-bits 4 --q-group-size 64

# Eval both precisions, both suites.
python eval_ood.py     --model "$FUSED" --out "${RESULTS}/ood_v5_dpo.json"
python eval_meaning.py --model "$FUSED" --out "${RESULTS}/meaning_v5_dpo.json"
python eval_ood.py     --model "$QUANT" --out "${RESULTS}/ood_v5_dpo_4bit.json"
python eval_meaning.py --model "$QUANT" --out "${RESULTS}/meaning_v5_dpo_4bit.json"

python - <<'PY'
import json
R = "/Users/hcserver/macwispr-polish-bench/results"
def s(f):
    return json.load(open(f"{R}/{f}"))["summary"]
rows = [
    ("v4-dpo100-4bit", s("ood_sft_v4_4bit.json"), s("meaning_v4_dpo100_4bit.json")),
    ("v5-dpo-4bit",    s("ood_v5_dpo_4bit.json"), s("meaning_v5_dpo_4bit.json")),
    ("v5-dpo-bf16",    s("ood_v5_dpo.json"),      s("meaning_v5_dpo.json")),
]
print(f"{'model':18s} {'ood':>8s} {'meaning':>8s} {'facts':>7s}")
for name, o, m in rows:
    print(f"{name:18s} {o['pass']:>8s} {m['pass']:>8s} {m['fact_retention']:>7.3f}")
PY
echo "DPO_V5_OK $(date -Iseconds)"
