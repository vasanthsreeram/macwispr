#!/usr/bin/env bash
# Standalone GRPO run on the SFT checkpoint (post DPO-regression finding).
# Targets weak tags: multi_list / mixed_styles / format_numbered.
# Fuses + evals; only quantizes if it beats the SFT baseline on the OOD suite.
set -euo pipefail

BASE="${HOME}/.cache/macwispr-minicpm-bench"
BENCH="${HOME}/macwispr-polish-bench"
PP="${BASE}/polish_posttrain"
# shellcheck disable=SC1091
source "${BASE}/.venv312/bin/activate"
export PYTHONPATH="${PP}${PYTHONPATH:+:$PYTHONPATH}"
cd "$PP"

SFT_FUSED="${BENCH}/fused/qwen35-08b-polish-structure-v2"
ADAPTER="${BENCH}/adapters/qwen35-08b-polish-structure-v2-grpo2"
FUSED="${BENCH}/fused/qwen35-08b-polish-structure-v2-grpo2"
QUANT="${BENCH}/fused/qwen35-08b-polish-structure-v2-grpo2-4bit"
RESULTS="${BENCH}/results"
ITERS="${ITERS:-300}"

echo "=== GRPO-on-SFT start $(date -Iseconds) iters=$ITERS ==="

python - <<'PY'
import json
from pathlib import Path
pp = Path.home() / ".cache/macwispr-minicpm-bench/polish_posttrain"
prompts = [json.loads(l) for l in (pp / "dpo_prompts.jsonl").read_text().splitlines() if l.strip()]
hard = [p for p in prompts if any(t in p["tags"] for t in ("multi_list", "mixed_styles", "format_numbered", "format_checklist"))]
SYSTEM = "Clean up the dictated text. Output only the polished text."
rows = [
    {
        "prompt": f"### Input:\n{p['raw']}\n\n### Output:\n",
        "answer": (p.get("gold") or "").strip(),
        "system": SYSTEM,
        "type": ",".join(p["tags"]),
    }
    for p in hard
    if (p.get("gold") or "").strip()
]
data = pp / "grpo_data"
data.mkdir(exist_ok=True)
split = max(1, int(len(rows) * 0.9))
(data / "train.jsonl").write_text("\n".join(json.dumps(r) for r in rows[:split]) + "\n")
(data / "valid.jsonl").write_text("\n".join(json.dumps(r) for r in rows[split:]) + "\n")
print(f"grpo train={split} valid={len(rows)-split}")
PY

rm -rf "$ADAPTER"
mkdir -p "$ADAPTER"

python -m mlx_lm_lora.train \
  --model "$SFT_FUSED" \
  --train \
  --train-mode grpo \
  --train-type lora \
  --data "${PP}/grpo_data" \
  --batch-size 1 \
  --iters "$ITERS" \
  --learning-rate 5e-6 \
  --adapter-path "$ADAPTER" \
  --group-size 4 \
  --max-completion-length 256 \
  --reward-functions-file "${PP}/grpo_rewards.py" \
  --reward-functions polish_reward \
  --steps-per-report 10 \
  --save-every 50 \
  --seed 42

rm -rf "$FUSED"
mlx_lm.fuse --model "$SFT_FUSED" --adapter-path "$ADAPTER" --save-path "$FUSED"
for f in tokenizer.json tokenizer_config.json chat_template.jinja; do
  [[ ! -f "$FUSED/$f" && -f "$SFT_FUSED/$f" ]] && cp "$SFT_FUSED/$f" "$FUSED/"
done

python eval_ood.py --model "$FUSED" --suite "${PP}/ood_eval_set.jsonl" --out "${RESULTS}/ood_sft_v2_grpo2.json"

GRPO_RATE=$(python3 -c "import json;print(json.load(open('${RESULTS}/ood_sft_v2_grpo2.json'))['summary']['pass_rate'])")
SFT_RATE=$(python3 -c "import json;print(json.load(open('${RESULTS}/ood_sft_v2.json'))['summary']['pass_rate'])")
echo "gate: sft=$SFT_RATE grpo2=$GRPO_RATE"

if python3 -c "import sys; sys.exit(0 if $GRPO_RATE > $SFT_RATE else 1)"; then
  echo "GRPO beats SFT — quantizing"
  rm -rf "$QUANT"
  mlx_lm.convert --hf-path "$FUSED" --mlx-path "$QUANT" -q --q-bits 4 --q-group-size 64
  python eval_ood.py --model "$QUANT" --suite "${PP}/ood_eval_set.jsonl" --out "${RESULTS}/ood_sft_v2_grpo2_4bit.json"
  python rebuild_comparison.py \
    --local "${RESULTS}/ood_sft_v2_grpo2_4bit.json" \
    --cached "${RESULTS}/bench_vs_claude_sonnet.json" \
    --local-name "Local Qwen 4-bit (SFT+GRPO)" \
    --out "${RESULTS}/bench_vs_claude_sonnet_v3"
else
  echo "GRPO did not beat SFT — keeping SFT as best"
fi
echo "GRPO_RUN_OK $(date -Iseconds)"
