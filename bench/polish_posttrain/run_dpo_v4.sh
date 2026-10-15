#!/usr/bin/env bash
# DPO on SFT v4 with composite reward (polish_verifier + 2x fact_retention).
# Pairs: best-of-8 from v4 over 370 prompts (150 fact-dense + 220 structure).
# Then fuse, quantize, and run the FULL bench set on both precisions.
set -euo pipefail

BASE="${HOME}/.cache/macwispr-minicpm-bench"
BENCH="${HOME}/macwispr-polish-bench"
PP="${BASE}/polish_posttrain"
# shellcheck disable=SC1091
source "${BASE}/.venv312/bin/activate"
export PYTHONPATH="${PP}${PYTHONPATH:+:$PYTHONPATH}"
cd "$PP"

V4_FUSED="${BENCH}/fused/qwen35-08b-polish-structure-v4"
ADAPTER="${BENCH}/adapters/qwen35-08b-polish-v4-dpo"
FUSED="${BENCH}/fused/qwen35-08b-polish-v4-dpo"
QUANT="${BENCH}/fused/qwen35-08b-polish-v4-dpo-4bit"
RESULTS="${BENCH}/results"

echo "=== DPO v4 start $(date -Iseconds) ==="

python gen_dpo_pairs.py \
  --model "$V4_FUSED" \
  --prompts "${PP}/data/dpo_prompts_v4.jsonl" \
  --out "${PP}/data/dpo_pairs_v4.jsonl" \
  --n 8 --temp 0.9 --min-margin 0.5

python - <<'PY'
import json, random
from pathlib import Path
pp = Path.home() / ".cache/macwispr-minicpm-bench/polish_posttrain"
rows = [json.loads(l) for l in (pp / "data/dpo_pairs_v4.jsonl").read_text().splitlines() if l.strip()]
rng = random.Random(5); rng.shuffle(rows)
n_val = max(10, len(rows) // 20)
out = pp / "dpo_v4_data"; out.mkdir(exist_ok=True)
(out / "valid.jsonl").write_text("\n".join(json.dumps(r) for r in rows[:n_val]) + "\n")
(out / "train.jsonl").write_text("\n".join(json.dumps(r) for r in rows[n_val:]) + "\n")
print(f"dpo_v4 data: train={len(rows)-n_val} valid={n_val}")
PY

rm -rf "$ADAPTER"
mlx_lm_lora.train \
  --model "$V4_FUSED" \
  --train \
  --train-mode dpo \
  --train-type lora \
  --data "${PP}/dpo_v4_data" \
  --batch-size 2 \
  --iters 400 \
  --learning-rate 5e-6 \
  --beta 0.1 \
  --max-seq-length 1024 \
  --adapter-path "$ADAPTER" \
  --save-every 100 \
  --steps-per-eval 100 \
  --steps-per-report 20 \
  --seed 42

rm -rf "$FUSED"
mlx_lm.fuse --model "$V4_FUSED" --adapter-path "$ADAPTER" --save-path "$FUSED"
rm -rf "$QUANT"
mlx_lm.convert --hf-path "$FUSED" --mlx-path "$QUANT" -q --q-bits 4 --q-group-size 64

# Full bench set, both precisions
python eval_ood.py --model "$FUSED" --out "${RESULTS}/ood_v4_dpo.json"
python eval_meaning.py --model "$FUSED" --out "${RESULTS}/meaning_v4_dpo.json"
python eval_ood.py --model "$QUANT" --out "${RESULTS}/ood_v4_dpo_4bit.json"
python eval_meaning.py --model "$QUANT" --out "${RESULTS}/meaning_v4_dpo_4bit.json"

python - <<'PY'
import json
R = "/Users/hcserver/macwispr-polish-bench/results"
def s(f):
    d = json.load(open(f"{R}/{f}"))["summary"]
    return d
rows = [
    ("v3-4bit", s("ood_sft_v3_4bit_rescored.json"), s("meaning_v3_4bit.json")),
    ("v4-4bit", s("ood_sft_v4_4bit.json"), s("meaning_v4_4bit.json")),
    ("v4-dpo-4bit", s("ood_v4_dpo_4bit.json"), s("meaning_v4_dpo_4bit.json")),
]
print(f"{'model':14s} {'ood':>8s} {'meaning':>8s} {'facts':>7s}")
for name, o, m in rows:
    print(f"{name:14s} {o['pass']:>8s} {m['pass']:>8s} {m['fact_retention']:>7.3f}")
best = max(rows[1:], key=lambda r: (r[2]["fact_retention"], r[1]["pass_rate"]))
print(f"SHIP_CANDIDATE {best[0]}")
PY
echo "DPO_V4_OK $(date -Iseconds)"
