#!/usr/bin/env bash
# SFT v3: continue-train structure-v2 SFT on synthetic hard-tag data (grok-generated,
# verifier-validated) mixed with replay of the original pool to prevent forgetting.
# Gate is on the 4-BIT eval (what we ship), vs the SFT-4bit baseline.
set -euo pipefail

BASE="${HOME}/.cache/macwispr-minicpm-bench"
BENCH="${HOME}/macwispr-polish-bench"
PP="${BASE}/polish_posttrain"
# shellcheck disable=SC1091
source "${BASE}/.venv312/bin/activate"
export PYTHONPATH="${PP}${PYTHONPATH:+:$PYTHONPATH}"
cd "$PP"

SFT_FUSED="${BENCH}/fused/qwen35-08b-polish-structure-v2"
ADAPTER="${BENCH}/adapters/qwen35-08b-polish-structure-v3"
FUSED="${BENCH}/fused/qwen35-08b-polish-structure-v3"
QUANT="${BENCH}/fused/qwen35-08b-polish-structure-v3-4bit"
RESULTS="${BENCH}/results"
DATA="${PP}/sft_v3_data"
ITERS="${ITERS:-1000}"
REPLAY="${REPLAY:-900}"

echo "=== SFT v3 start $(date -Iseconds) iters=$ITERS replay=$REPLAY ==="

python - <<PY
import json, random
from pathlib import Path
pp = Path.home() / ".cache/macwispr-minicpm-bench/polish_posttrain"
bench = Path.home() / "macwispr-polish-bench"
rng = random.Random(17)

synth = [json.loads(l) for l in (pp / "synth_hard.jsonl").read_text().splitlines() if l.strip()]
synth_rows = [{"text": f"### Input:\n{r['raw']}\n\n### Output:\n{r['gold']}"} for r in synth]

orig = [json.loads(l) for l in (bench / "data/train.jsonl").read_text().splitlines() if l.strip()]
replay = rng.sample(orig, min($REPLAY, len(orig)))

rows = synth_rows + replay
rng.shuffle(rows)
n_val = max(20, len(rows) // 20)
out = pp / "sft_v3_data"
out.mkdir(exist_ok=True)
(out / "valid.jsonl").write_text("\n".join(json.dumps(r) for r in rows[:n_val]) + "\n")
(out / "train.jsonl").write_text("\n".join(json.dumps(r) for r in rows[n_val:]) + "\n")
print(f"sft_v3 data: synth={len(synth_rows)} replay={len(replay)} train={len(rows)-n_val} valid={n_val}")
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
  --model "$SFT_FUSED" \
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
mlx_lm.fuse --model "$SFT_FUSED" --adapter-path "$ADAPTER" --save-path "$FUSED"

python eval_ood.py --model "$FUSED" --suite "${PP}/ood_eval_set.jsonl" --out "${RESULTS}/ood_sft_v3.json"

rm -rf "$QUANT"
mlx_lm.convert --hf-path "$FUSED" --mlx-path "$QUANT" -q --q-bits 4 --q-group-size 64
python eval_ood.py --model "$QUANT" --suite "${PP}/ood_eval_set.jsonl" --out "${RESULTS}/ood_sft_v3_4bit.json"

V3=$(python3 -c "import json;print(json.load(open('${RESULTS}/ood_sft_v3_4bit.json'))['summary']['pass_rate'])")
BASELINE=$(python3 -c "import json;print(json.load(open('${RESULTS}/ood_sft_v2_4bit.json'))['summary']['pass_rate'])")
echo "gate(4bit): v2=$BASELINE v3=$V3"
if python3 -c "import sys; sys.exit(0 if $V3 > $BASELINE else 1)"; then
  echo "v3 beats v2 at 4-bit — rebuilding Sonnet comparison"
  python rebuild_comparison.py \
    --local "${RESULTS}/ood_sft_v3_4bit.json" \
    --cached "${RESULTS}/bench_vs_claude_sonnet.json" \
    --local-name "Local Qwen 4-bit (SFT v3 + synth data)" \
    --out "${RESULTS}/bench_vs_claude_sonnet_v4"
else
  echo "v3 does not beat v2 at 4-bit — keeping v2"
fi
echo "SFT_V3_OK $(date -Iseconds)"
