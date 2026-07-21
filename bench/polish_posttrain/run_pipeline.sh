#!/usr/bin/env bash
# Post-SFT pipeline on Mac Studio: wait → fuse → OOD eval → DPO → re-eval → 4-bit → summary
set -euo pipefail

BASE="${HOME}/.cache/macwispr-minicpm-bench"
BENCH="${HOME}/macwispr-polish-bench"
PP="${BASE}/polish_posttrain"
VENV="${BASE}/.venv312"
# shellcheck disable=SC1091
source "${VENV}/bin/activate"
export PYTHONPATH="${PP}${PYTHONPATH:+:$PYTHONPATH}"
cd "$PP"

SFT_ADAPTER="${BENCH}/adapters/qwen35-08b-polish-structure-v2"
SFT_FUSED="${BENCH}/fused/qwen35-08b-polish-structure-v2"
DPO_ADAPTER="${BENCH}/adapters/qwen35-08b-polish-structure-v2-dpo"
DPO_FUSED="${BENCH}/fused/qwen35-08b-polish-structure-v2-dpo"
QUANT_OUT="${BENCH}/fused/qwen35-08b-polish-structure-v2-dpo-4bit"
ENUM="${BENCH}/fused/qwen35-08b-polish-enum"
RESULTS="${BENCH}/results"
TARGET_ITERS=2400
mkdir -p "$RESULTS" "$BENCH/logs" "$DPO_ADAPTER"

LOG="${BENCH}/logs/pipeline_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOG") 2>&1
echo "=== PIPELINE START $(date -Iseconds) ==="
echo "log=$LOG"
echo "host=$(hostname) mlx_lm=$(python -c 'import mlx_lm; print(mlx_lm.__version__)')"

sft_training_running() {
  # Parent train script pid is reliable (macOS truncates long ps command lines)
  local pid_file="${BENCH}/logs/structure_sft_v2.pid"
  if [[ -f "$pid_file" ]]; then
    local p
    p=$(cat "$pid_file")
    if kill -0 "$p" 2>/dev/null; then
      return 0
    fi
  fi
  # fallback: short pattern only
  if ps -axo command 2>/dev/null | grep -v grep | grep -q 'bin/mlx_lm.lora'; then
    return 0
  fi
  return 1
}

last_train_iter() {
  local sft_log="$1"
  python3 -c "
import re
from pathlib import Path
p=Path('''$sft_log''')
if not p.exists():
    print(0); raise SystemExit
xs=[int(x) for x in re.findall(r'Iter (\\d+): Train loss', p.read_text())]
print(xs[-1] if xs else 0)
"
}

wait_sft() {
  local logpath_file="${BENCH}/logs/structure_sft_v2.logpath"
  echo "--- wait for SFT (TRAIN_OK or completed ~${TARGET_ITERS} iters) ---"
  local sft_log=""
  [[ -f "$logpath_file" ]] && sft_log=$(cat "$logpath_file")

  # Never trust mid-train fuse
  if sft_training_running; then
    echo "SFT still training — ensure no premature fuse dir"
    rm -rf "$SFT_FUSED"
  fi

  if [[ -f "$SFT_FUSED/model.safetensors" && -n "$sft_log" && -f "$sft_log" ]] && grep -q 'TRAIN_OK' "$sft_log"; then
    local sz
    sz=$(stat -f%z "$SFT_FUSED/model.safetensors" 2>/dev/null || echo 0)
    if [[ "$sz" -gt 1400000000 ]]; then
      echo "SFT fused present after TRAIN_OK ($sz bytes)"
      return 0
    fi
  fi

  while true; do
    if [[ -n "$sft_log" && -f "$sft_log" ]] && grep -q 'TRAIN_OK' "$sft_log"; then
      echo "SFT TRAIN_OK in log"
      break
    fi
    local it=0
    if [[ -n "$sft_log" && -f "$sft_log" ]]; then
      it=$(last_train_iter "$sft_log")
    fi
    if sft_training_running; then
      echo "SFT running iter≈${it}/${TARGET_ITERS} $(date +%H:%M:%S)"
      sleep 90
      continue
    fi
    # process not running
    echo "SFT process not running at iter≈${it}"
    if [[ -n "$sft_log" && -f "$sft_log" ]]; then
      tail -40 "$sft_log" || true
    fi
    if [[ "$it" -ge $((TARGET_ITERS - 10)) ]]; then
      echo "Near target iters — proceed to fuse"
      break
    fi
    # maybe fuse step of train script still running under different pid briefly
    sleep 45
    if sft_training_running; then
      continue
    fi
    if [[ "$it" -ge $((TARGET_ITERS - 10)) ]]; then
      break
    fi
    echo "ERROR: SFT ended early at iter=$it (need ~$TARGET_ITERS)" >&2
    exit 1
  done
}

fuse_if_needed() {
  echo "--- fuse SFT ---"
  if [[ -f "$SFT_FUSED/model.safetensors" ]] && [[ $(stat -f%z "$SFT_FUSED/model.safetensors") -gt 1400000000 ]]; then
    local logpath_file="${BENCH}/logs/structure_sft_v2.logpath"
    local sft_log=""
    [[ -f "$logpath_file" ]] && sft_log=$(cat "$logpath_file")
    if [[ -n "$sft_log" && -f "$sft_log" ]] && grep -q 'TRAIN_OK' "$sft_log"; then
      echo "already fused after TRAIN_OK: $SFT_FUSED"
      return 0
    fi
  fi
  rm -rf "$SFT_FUSED"
  mkdir -p "$SFT_FUSED"
  if [[ -f "$SFT_ADAPTER/config.json" && -f "$SFT_ADAPTER/model.safetensors" ]]; then
    cp -R "$SFT_ADAPTER"/. "$SFT_FUSED/"
  elif [[ -f "$SFT_ADAPTER/adapters.safetensors" ]]; then
    echo "fusing adapters.safetensors onto enum base..."
    mlx_lm.fuse --model "$ENUM" --adapter-path "$SFT_ADAPTER" --save-path "$SFT_FUSED"
  else
    echo "ERROR: no SFT weights in $SFT_ADAPTER" >&2
    ls -la "$SFT_ADAPTER" || true
    exit 1
  fi
  for f in tokenizer.json tokenizer_config.json chat_template.jinja config.json model.safetensors.index.json; do
    if [[ ! -f "$SFT_FUSED/$f" && -f "$ENUM/$f" ]]; then
      cp "$ENUM/$f" "$SFT_FUSED/"
    fi
  done
  local fsz
  fsz=$(stat -f%z "$SFT_FUSED/model.safetensors" 2>/dev/null || echo 0)
  echo "fused -> $SFT_FUSED size=$fsz ($(du -sh "$SFT_FUSED" | awk '{print $1}'))"
  if [[ "$fsz" -lt 1000000000 ]]; then
    echo "ERROR: fused model too small" >&2
    exit 1
  fi
}

run_eval() {
  local model="$1"
  local name="$2"
  echo "--- OOD eval: $name ---"
  local out="${RESULTS}/ood_${name}.json"
  python "${PP}/eval_ood.py" --model "$model" --suite "${PP}/ood_eval_set.jsonl" --out "$out"
  echo "wrote $out"
  python -c "
import json
from pathlib import Path
out_path = Path('''$out''')
name = '''$name'''
results = Path('''$RESULTS''')
d = json.loads(out_path.read_text())
s = d['summary']
print('SUMMARY', name, s)
(results / f'summary_{name}.txt').write_text(json.dumps(s, indent=2))
"
}

gen_dpo() {
  echo "--- gen DPO pairs (best-of-8) ---"
  local out="${PP}/dpo_pairs.jsonl"
  python "${PP}/gen_dpo_pairs.py" \
    --model "$SFT_FUSED" \
    --prompts "${PP}/dpo_prompts.jsonl" \
    --out "$out" \
    --n 8 \
    --temp 0.9 \
    --min-margin 0.35 \
    --max-tokens 512
  python - <<'PY'
import json
from pathlib import Path
from polish_verifier import verify

pp = Path.home() / ".cache/macwispr-minicpm-bench/polish_posttrain"
pairs_path = pp / "dpo_pairs.jsonl"
prompts = [json.loads(l) for l in (pp / "dpo_prompts.jsonl").read_text().splitlines() if l.strip()]
existing = pairs_path.read_text() if pairs_path.exists() else ""
n_add = 0
with pairs_path.open("a") as f:
    for p in prompts:
        gold = (p.get("gold") or "").strip()
        if not gold:
            continue
        tags = p["tags"]
        flat = " ".join(gold.split())
        v_g = verify(p["raw"], gold, tags)
        v_b = verify(p["raw"], flat, tags)
        if v_g.score - v_b.score < 0.3:
            continue
        prompt = f"### Input:\n{p['raw']}\n\n### Output:\n"
        if prompt in existing:
            continue
        f.write(json.dumps({
            "prompt": prompt,
            "chosen": gold,
            "rejected": flat,
            "margin": round(v_g.score - v_b.score, 3),
            "tags": tags,
            "source": "gold_vs_flat",
        }) + "\n")
        n_add += 1
print(f"added {n_add} gold_vs_flat pairs")
n = sum(1 for _ in pairs_path.open()) if pairs_path.exists() else 0
print("total pairs", n)
if n < 20:
    raise SystemExit(f"too few DPO pairs: {n}")
PY
}

train_dpo() {
  echo "--- DPO train ---"
  local data_dir="${PP}/dpo_data"
  mkdir -p "$data_dir"
  python - <<'PY'
import json
from pathlib import Path
pp = Path.home() / ".cache/macwispr-minicpm-bench/polish_posttrain"
pairs = [json.loads(l) for l in (pp / "dpo_pairs.jsonl").read_text().splitlines() if l.strip()]
rows = [{"prompt": r["prompt"], "chosen": r["chosen"], "rejected": r["rejected"]} for r in pairs]
n = len(rows)
if n < 20:
    raise SystemExit(f"too few DPO pairs: {n}")
split = max(1, int(n * 0.9))
data = pp / "dpo_data"
data.mkdir(exist_ok=True)
(data / "train.jsonl").write_text("\n".join(json.dumps(r) for r in rows[:split]) + "\n")
(data / "valid.jsonl").write_text("\n".join(json.dumps(r) for r in rows[split:]) + "\n")
print(f"dpo train={split} valid={n-split}")
PY

  rm -rf "$DPO_ADAPTER"
  mkdir -p "$DPO_ADAPTER"
  if ! python -c "import mlx_lm_lora" 2>/dev/null; then
    echo "mlx-lm-lora not installed" >&2
    exit 1
  fi
  python -m mlx_lm_lora.train \
    --model "$SFT_FUSED" \
    --train \
    --train-mode dpo \
    --train-type lora \
    --data "$data_dir" \
    --batch-size 2 \
    --iters 400 \
    --learning-rate 5e-6 \
    --adapter-path "$DPO_ADAPTER" \
    --steps-per-report 10 \
    --steps-per-eval 50 \
    --save-every 100 \
    --max-seq-length 1024 \
    --beta 0.1 \
    --dpo-cpo-loss-type sigmoid \
    --seed 42

  rm -rf "$DPO_FUSED"
  mkdir -p "$DPO_FUSED"
  if [[ -f "$DPO_ADAPTER/model.safetensors" ]]; then
    cp -R "$DPO_ADAPTER"/. "$DPO_FUSED/"
  elif [[ -f "$DPO_ADAPTER/adapters.safetensors" ]]; then
    mlx_lm.fuse --model "$SFT_FUSED" --adapter-path "$DPO_ADAPTER" --save-path "$DPO_FUSED"
  else
    echo "ERROR: DPO produced no adapters" >&2
    ls -la "$DPO_ADAPTER" || true
    exit 1
  fi
  for f in tokenizer.json tokenizer_config.json chat_template.jinja config.json model.safetensors.index.json; do
    if [[ ! -f "$DPO_FUSED/$f" && -f "$SFT_FUSED/$f" ]]; then
      cp "$SFT_FUSED/$f" "$DPO_FUSED/"
    fi
  done
  echo "DPO fused -> $DPO_FUSED ($(du -sh "$DPO_FUSED" | awk '{print $1}'))"
}

maybe_grpo() {
  echo "--- gate check for GRPO ---"
  local summary="${RESULTS}/ood_sft_v2_dpo.json"
  if [[ ! -f "$summary" ]]; then
    echo "no dpo ood results; skip GRPO"
    return 0
  fi
  set +e
  python - <<'PY'
import json, sys
from pathlib import Path
p = Path.home() / "macwispr-polish-bench/results/ood_sft_v2_dpo.json"
d = json.loads(p.read_text())
by = d["summary"].get("by_tag", {})
def rate(key):
    s = by.get(key, "0/1")
    a,b = s.split("/")
    return int(a)/max(1,int(b)), s
ml, mls = rate("multi_list")
mx, mxs = rate("mixed_styles")
print(f"multi_list={mls} mixed={mxs}")
need = ml < 0.80 or mx < 0.80
Path.home().joinpath("macwispr-polish-bench/results/grpo_needed.txt").write_text(
    f"multi_list={mls} mixed={mxs} need_grpo={need}\n"
)
sys.exit(0 if need else 1)
PY
  local need=$?
  set -e
  if [[ $need -ne 0 ]]; then
    echo "Gates OK (>=80% multi_list/mixed) — skip GRPO"
    echo "gates_ok multi_list/mixed >= 80%" > "${RESULTS}/grpo_skipped.txt"
    return 0
  fi
  echo "Gates below 80% — attempt GRPO on hard tags (mlx-lm-lora)"
  local grpo_data="${PP}/grpo_data"
  mkdir -p "$grpo_data"
  python - <<'PY'
import json
from pathlib import Path
pp = Path.home()/".cache/macwispr-minicpm-bench/polish_posttrain"
prompts = [json.loads(l) for l in (pp/"dpo_prompts.jsonl").read_text().splitlines() if l.strip()]
hard = [p for p in prompts if any(t in p["tags"] for t in ("multi_list","mixed_styles","format_numbered"))]
# GRPO contract (mlx_lm_lora GRPODataset): each row needs prompt + answer;
# system overrides the default R1 <think>/<answer> system prompt, type carries
# tags to the reward function. Rows without a gold answer are skipped.
SYSTEM = "Clean up the dictated text. Output only the polished text."
rows = [
    {
        "prompt": f"### Input:\n{p['raw']}\n\n### Output:\n",
        "answer": (p.get("gold") or "").strip(),
        "system": SYSTEM,
        "type": ",".join(p["tags"]),
    }
    for p in hard[:80]
    if (p.get("gold") or "").strip()
]
data = pp/"grpo_data"
data.mkdir(exist_ok=True)
(data/"train.jsonl").write_text("\n".join(json.dumps(r) for r in rows[:70])+"\n")
(data/"valid.jsonl").write_text("\n".join(json.dumps(r) for r in rows[70:])+"\n")
print("grpo prompts", len(rows))
PY
  local GRPO_ADAPTER="${BENCH}/adapters/qwen35-08b-polish-structure-v2-grpo"
  rm -rf "$GRPO_ADAPTER"
  mkdir -p "$GRPO_ADAPTER"
  set +e
  python -m mlx_lm_lora.train \
    --model "$BEST" \
    --train \
    --train-mode grpo \
    --train-type lora \
    --data "$grpo_data" \
    --batch-size 1 \
    --iters 100 \
    --learning-rate 5e-6 \
    --adapter-path "$GRPO_ADAPTER" \
    --group-size 4 \
    --max-completion-length 256 \
    --reward-functions-file "${PP}/grpo_rewards.py" \
    --reward-functions polish_reward \
    --seed 42 \
    > "${BENCH}/logs/grpo_train.log" 2>&1
  local grc=$?
  set -e
  if [[ $grc -ne 0 ]]; then
    echo "GRPO failed/blocked — capture error"
    tail -40 "${BENCH}/logs/grpo_train.log" || true
    {
      echo "GRPO attempt failed with exit $grc"
      echo "See grpo_train.log"
      tail -20 "${BENCH}/logs/grpo_train.log"
    } > "${RESULTS}/grpo_blocked.txt"
    return 0
  fi
  local GRPO_FUSED="${BENCH}/fused/qwen35-08b-polish-structure-v2-grpo"
  rm -rf "$GRPO_FUSED"
  if [[ -f "$GRPO_ADAPTER/adapters.safetensors" ]]; then
    mlx_lm.fuse --model "$BEST" --adapter-path "$GRPO_ADAPTER" --save-path "$GRPO_FUSED"
    run_eval "$GRPO_FUSED" "sft_v2_grpo" || true
  fi
}

pass_rate() {
  python3 -c "
import json, sys
from pathlib import Path
p = Path('$RESULTS') / ('ood_' + sys.argv[1] + '.json')
print(json.loads(p.read_text())['summary']['pass_rate'] if p.exists() else -1)
" "$1"
}

quantize() {
  local src="$1"
  local dst="$2"
  echo "--- 4-bit quant from $src ---"
  rm -rf "$dst"
  mlx_lm.convert --hf-path "$src" --mlx-path "$dst" -q --q-bits 4 --q-group-size 64
  echo "quant -> $dst ($(du -sh "$dst" | awk '{print $1}'))"
}

# ---------- main ----------
wait_sft
fuse_if_needed

run_eval "$SFT_FUSED" "sft_v2"

gen_dpo
train_dpo
run_eval "$DPO_FUSED" "sft_v2_dpo"

# Gate: DPO must beat SFT on the OOD suite, else keep SFT
SFT_RATE=$(pass_rate sft_v2)
DPO_RATE=$(pass_rate sft_v2_dpo)
BEST="$SFT_FUSED"
if python3 -c "import sys; sys.exit(0 if $DPO_RATE > $SFT_RATE else 1)"; then
  BEST="$DPO_FUSED"
fi
echo "gate: sft=$SFT_RATE dpo=$DPO_RATE -> BEST=$BEST"

maybe_grpo

GRPO_RATE=$(pass_rate sft_v2_grpo)
BEST_RATE=$(python3 -c "print(max($SFT_RATE, $DPO_RATE))")
if [[ -f "${BENCH}/fused/qwen35-08b-polish-structure-v2-grpo/model.safetensors" ]] \
   && python3 -c "import sys; sys.exit(0 if $GRPO_RATE > $BEST_RATE else 1)"; then
  BEST="${BENCH}/fused/qwen35-08b-polish-structure-v2-grpo"
fi
echo "BEST for quant: $BEST"
quantize "$BEST" "$QUANT_OUT"
run_eval "$QUANT_OUT" "sft_v2_dpo_4bit"

echo "=== PIPELINE DONE $(date -Iseconds) ==="
echo "ARTIFACTS:"
echo "  SFT:   $SFT_FUSED"
echo "  DPO:   $DPO_FUSED"
echo "  BEST:  $BEST"
echo "  4bit:  $QUANT_OUT"
echo "  results: $RESULTS"
ls -la "$RESULTS"
echo "PIPELINE_OK"
