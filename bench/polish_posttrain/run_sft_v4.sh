#!/usr/bin/env bash
# SFT v4: continue-train structure-v3 on fact-retention data (deterministic
# template golds: spelled money/phone/password/negations) + replay of the
# original pool. Gate: 4-bit must beat v3-4bit on the MEANING bench without
# losing more than 2 cases on the OOD structure bench.
set -euo pipefail

BASE="${HOME}/.cache/macwispr-minicpm-bench"
BENCH="${HOME}/macwispr-polish-bench"
PP="${BASE}/polish_posttrain"
# shellcheck disable=SC1091
source "${BASE}/.venv312/bin/activate"
export PYTHONPATH="${PP}${PYTHONPATH:+:$PYTHONPATH}"
cd "$PP"

V3_FUSED="${BENCH}/fused/qwen35-08b-polish-structure-v3"
ADAPTER="${BENCH}/adapters/qwen35-08b-polish-structure-v4"
FUSED="${BENCH}/fused/qwen35-08b-polish-structure-v4"
QUANT="${BENCH}/fused/qwen35-08b-polish-structure-v4-4bit"
RESULTS="${BENCH}/results"
DATA="${PP}/sft_v4_data"
ITERS="${ITERS:-800}"
REPLAY="${REPLAY:-900}"

echo "=== SFT v4 start $(date -Iseconds) iters=$ITERS replay=$REPLAY ==="

python - <<PY
import json, random
from pathlib import Path
pp = Path.home() / ".cache/macwispr-minicpm-bench/polish_posttrain"
rng = random.Random(23)

fact = [json.loads(l) for l in (pp / "data/fact_sft.jsonl").read_text().splitlines() if l.strip()]
fact_rows = [{"text": r["text"]} for r in fact]

orig = [json.loads(l) for l in (Path.home() / ".cache/macwispr-minicpm-bench/bench_sync/qwen35_structure_sft/train.jsonl").read_text().splitlines() if l.strip()]
replay = rng.sample(orig, min($REPLAY, len(orig)))

rows = fact_rows + replay
rng.shuffle(rows)
n_val = max(20, len(rows) // 20)
out = pp / "sft_v4_data"
out.mkdir(exist_ok=True)
(out / "valid.jsonl").write_text("\n".join(json.dumps(r) for r in rows[:n_val]) + "\n")
(out / "train.jsonl").write_text("\n".join(json.dumps(r) for r in rows[n_val:]) + "\n")
print(f"sft_v4 data: fact={len(fact_rows)} replay={len(replay)} train={len(rows)-n_val} valid={n_val}")
PY

rm -rf "$ADAPTER"
mkdir -p "$ADAPTER"
cat > "$ADAPTER/train_config.yaml" <<EOF
lora_parameters:
  rank: 16
  dropout: 0.0
  scale: 20.0
EOF

mlx_lm.lora \
  --model "$V3_FUSED" \
  --train \
  --data "$DATA" \
  --fine-tune-type lora \
  --batch-size 4 \
  --iters "$ITERS" \
  --learning-rate 1e-5 \
  --num-layers -1 \
  --max-seq-length 1024 \
  --adapter-path "$ADAPTER" \
  --save-every 200 \
  --steps-per-eval 100 \
  --steps-per-report 20 \
  --seed 42 \
  -c "$ADAPTER/train_config.yaml"

rm -rf "$FUSED"
mlx_lm.fuse --model "$V3_FUSED" --adapter-path "$ADAPTER" --save-path "$FUSED"

python eval_ood.py --model "$FUSED" --suite "${PP}/ood_eval_set.jsonl" --out "${RESULTS}/ood_sft_v4.json"
python eval_meaning.py --model "$FUSED" --suite "${PP}/meaning_eval_set.jsonl" --out "${RESULTS}/meaning_v4_bf16.json"

rm -rf "$QUANT"
mlx_lm.convert --hf-path "$FUSED" --mlx-path "$QUANT" -q --q-bits 4 --q-group-size 64
python eval_ood.py --model "$QUANT" --suite "${PP}/ood_eval_set.jsonl" --out "${RESULTS}/ood_sft_v4_4bit.json"
python eval_meaning.py --model "$QUANT" --suite "${PP}/meaning_eval_set.jsonl" --out "${RESULTS}/meaning_v4_4bit.json"

python - <<'PY'
import json
R = "/Users/hcserver/macwispr-polish-bench/results"
m4 = json.load(open(f"{R}/meaning_v4_4bit.json"))["summary"]
m3 = json.load(open(f"{R}/meaning_v3_4bit.json"))["summary"]
o4 = json.load(open(f"{R}/ood_sft_v4_4bit.json"))["summary"]
o3 = json.load(open(f"{R}/ood_sft_v3_4bit_rescored.json"))["summary"]
print(f"gate(4bit): meaning v3={m3['fact_retention']} v4={m4['fact_retention']}  ood v3={o3['pass_rate']} v4={o4['pass_rate']}")
ok = m4["fact_retention"] > m3["fact_retention"] and o4["pass_rate"] >= o3["pass_rate"] - 0.05
print("GATE_PASS" if ok else "GATE_FAIL")
PY
echo "SFT_V4_OK $(date -Iseconds)"
