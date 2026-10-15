#!/usr/bin/env bash
# GRPO on the SFT v3 checkpoint. RL prompts = synthetic hard-tag pool (heavy on
# numbered/multi_list, the remaining weak spots) + original hard dpo prompts.
# Chunked training (mlx_lm_lora GRPO leaks Metal memory). Gate on the 4-BIT eval
# vs v3's 0.625; only a winner gets quantized + a rebuilt Sonnet comparison.
set -euo pipefail

BASE="${HOME}/.cache/macwispr-minicpm-bench"
BENCH="${HOME}/macwispr-polish-bench"
PP="${BASE}/polish_posttrain"
# shellcheck disable=SC1091
source "${BASE}/.venv312/bin/activate"
export PYTHONPATH="${PP}${PYTHONPATH:+:$PYTHONPATH}"
cd "$PP"

V3_FUSED="${BENCH}/fused/qwen35-08b-polish-structure-v3"
ADAPTER="${BENCH}/adapters/qwen35-08b-polish-structure-v3-grpo"
FUSED="${BENCH}/fused/qwen35-08b-polish-structure-v3-grpo"
QUANT="${BENCH}/fused/qwen35-08b-polish-structure-v3-grpo-4bit"
RESULTS="${BENCH}/results"
ITERS="${ITERS:-300}"
CHUNK="${CHUNK:-25}"

echo "=== GRPO-on-v3 start $(date -Iseconds) iters=$ITERS ==="

python - <<'PY'
import json, random
from pathlib import Path
pp = Path.home() / ".cache/macwispr-minicpm-bench/polish_posttrain"
rng = random.Random(23)
SYSTEM = "Clean up the dictated text. Output only the polished text."

rows = []
synth = [json.loads(l) for l in (pp / "synth_hard.jsonl").read_text().splitlines() if l.strip()]
for r in synth:
    rows.append({"raw": r["raw"], "gold": r["gold"], "tags": r["tags"]})
prompts = [json.loads(l) for l in (pp / "dpo_prompts.jsonl").read_text().splitlines() if l.strip()]
for p in prompts:
    if any(t in p["tags"] for t in ("multi_list", "mixed_styles", "format_numbered", "format_checklist")):
        if (p.get("gold") or "").strip():
            rows.append({"raw": p["raw"], "gold": p["gold"].strip(), "tags": p["tags"]})

# weight numbered/multi_list higher: duplicate them once
hard = [r for r in rows if any(t in r["tags"] for t in ("format_numbered", "multi_list"))]
rows = rows + hard
rng.shuffle(rows)

grpo = [
    {
        "prompt": f"### Input:\n{r['raw']}\n\n### Output:\n",
        "answer": r["gold"],
        "system": SYSTEM,
        "type": ",".join(r["tags"]),
    }
    for r in rows
]
split = max(1, int(len(grpo) * 0.95))
data = pp / "grpo_data"
data.mkdir(exist_ok=True)
(data / "train.jsonl").write_text("\n".join(json.dumps(r) for r in grpo[:split]) + "\n")
(data / "valid.jsonl").write_text("\n".join(json.dumps(r) for r in grpo[split:]) + "\n")
print(f"grpo-on-v3 data: train={split} valid={len(grpo)-split} (numbered/multi_list double-weighted)")
PY

rm -rf "$ADAPTER"
mkdir -p "$ADAPTER"

DONE=0
CRASHES=0
RESUME=""
while (( DONE < ITERS )); do
  N=$(( ITERS - DONE < CHUNK ? ITERS - DONE : CHUNK ))
  set +e
  python -m mlx_lm_lora.train \
    --model "$V3_FUSED" \
    --train \
    --train-mode grpo \
    --train-type lora \
    --data "${PP}/grpo_data" \
    --batch-size 1 \
    --iters "$N" \
    --learning-rate 5e-6 \
    --adapter-path "$ADAPTER" \
    --group-size 3 \
    --max-completion-length 192 \
    --reward-functions-file "${PP}/grpo_rewards.py" \
    --reward-functions polish_reward \
    --steps-per-report 10 \
    --save-every "$CHUNK" \
    --seed $((42 + DONE + CRASHES)) \
    ${RESUME:+--resume-adapter-file "$RESUME"}
  rc=$?
  set -e
  [[ -f "$ADAPTER/adapters.safetensors" ]] && RESUME="$ADAPTER/adapters.safetensors"
  if (( rc == 0 )); then
    DONE=$((DONE + N))
    echo "chunk ok: $DONE/$ITERS iters"
  else
    CRASHES=$((CRASHES + 1))
    echo "chunk aborted rc=$rc (crash #$CRASHES) at ~$DONE iters — resuming"
    (( CRASHES >= 20 )) && { echo "too many crashes" >&2; exit 1; }
  fi
done

rm -rf "$FUSED"
mlx_lm.fuse --model "$V3_FUSED" --adapter-path "$ADAPTER" --save-path "$FUSED"
for f in tokenizer.json tokenizer_config.json chat_template.jinja; do
  [[ ! -f "$FUSED/$f" && -f "$V3_FUSED/$f" ]] && cp "$V3_FUSED/$f" "$FUSED/"
done

rm -rf "$QUANT"
mlx_lm.convert --hf-path "$FUSED" --mlx-path "$QUANT" -q --q-bits 4 --q-group-size 64
python eval_ood.py --model "$QUANT" --suite "${PP}/ood_eval_set.jsonl" --out "${RESULTS}/ood_v3_grpo_4bit.json"

G=$(python3 -c "import json;print(json.load(open('${RESULTS}/ood_v3_grpo_4bit.json'))['summary']['pass_rate'])")
B=$(python3 -c "import json;print(json.load(open('${RESULTS}/ood_sft_v3_4bit.json'))['summary']['pass_rate'])")
echo "gate(4bit): v3=$B v3-grpo=$G"
if python3 -c "import sys; sys.exit(0 if $G > $B else 1)"; then
  echo "GRPO beats v3 — rebuilding Sonnet comparison"
  python rebuild_comparison.py \
    --local "${RESULTS}/ood_v3_grpo_4bit.json" \
    --cached "${RESULTS}/bench_vs_claude_sonnet.json" \
    --local-name "Local Qwen 4-bit (SFT v3 + GRPO)" \
    --out "${RESULTS}/bench_vs_claude_sonnet_v5"
else
  echo "GRPO does not beat v3 — keeping v3"
fi
echo "GRPO_V3_OK $(date -Iseconds)"
