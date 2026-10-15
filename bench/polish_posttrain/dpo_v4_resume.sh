#!/usr/bin/env bash
# DPO v4 retry: batch 1 + seq 768 (batch-2/1024 hung at iter 1 on Metal).
# Pairs already mined in dpo_v4_data. Then fuse, quantize, full bench.
set -euo pipefail
BASE="${HOME}/.cache/macwispr-minicpm-bench"
BENCH="${HOME}/macwispr-polish-bench"
PP="${BASE}/polish_posttrain"
# shellcheck disable=SC1091
source "${BASE}/.venv312/bin/activate"
export PYTHONPATH="$PP"
cd "$PP"
V4="${BENCH}/fused/qwen35-08b-polish-structure-v4"
ADAPTER="${BENCH}/adapters/qwen35-08b-polish-v4-dpo"
FUSED="${BENCH}/fused/qwen35-08b-polish-v4-dpo"
QUANT="${BENCH}/fused/qwen35-08b-polish-v4-dpo-4bit"
RESULTS="${BENCH}/results"

rm -rf "$ADAPTER"
# Metal aborts (trap 6) kill this trainer at random iters; checkpoint every
# 50 and auto-resume until we accumulate 400 total iterations.
TOTAL=400
DONE=0
ATTEMPT=0
while [ "$DONE" -lt "$TOTAL" ] && [ "$ATTEMPT" -lt 15 ]; do
  ATTEMPT=$((ATTEMPT + 1))
  LEFT=$((TOTAL - DONE))
  RESUME=""
  if [ -f "$ADAPTER/adapters.safetensors" ]; then
    RESUME="--resume-adapter-file $ADAPTER/adapters.safetensors"
  fi
  echo "--- DPO attempt $ATTEMPT: $LEFT iters remaining (done=$DONE) ---"
  find "$ADAPTER" -name '[0-9]*_adapters.safetensors' -delete 2>/dev/null || true
  set +e
  mlx_lm_lora.train --model "$V4" --train --train-mode dpo --train-type lora \
    --data "${PP}/dpo_v4_data" --batch-size 1 --iters "$LEFT" \
    --learning-rate 5e-6 --beta 0.1 --max-seq-length 768 \
    --adapter-path "$ADAPTER" --save-every 50 \
    --steps-per-eval 100 --steps-per-report 20 --seed "$((42 + ATTEMPT))" \
    $RESUME
  rc=$?
  set -e
  if [ "$rc" -eq 0 ]; then
    DONE=$TOTAL
  else
    # count progress from newest numbered checkpoint this attempt
    ck=$(ls "$ADAPTER" 2>/dev/null | grep -oE '^[0-9]+' | sort -n | tail -1)
    DONE=$((DONE + ${ck:-0}))
    echo "--- trainer died rc=$rc, checkpointed ~${ck:-0} iters this attempt ---"
  fi
done
[ -f "$ADAPTER/adapters.safetensors" ] || { echo "NO_ADAPTER_PRODUCED"; exit 1; }

rm -rf "$FUSED"
mlx_lm.fuse --model "$V4" --adapter-path "$ADAPTER" --save-path "$FUSED"
rm -rf "$QUANT"
mlx_lm.convert --hf-path "$FUSED" --mlx-path "$QUANT" -q --q-bits 4 --q-group-size 64

python eval_ood.py --model "$FUSED" --out "${RESULTS}/ood_v4_dpo.json"
python eval_meaning.py --model "$FUSED" --out "${RESULTS}/meaning_v4_dpo.json"
python eval_ood.py --model "$QUANT" --out "${RESULTS}/ood_v4_dpo_4bit.json"
python eval_meaning.py --model "$QUANT" --out "${RESULTS}/meaning_v4_dpo_4bit.json"
echo "DPO_V4_OK $(date -Iseconds)"
