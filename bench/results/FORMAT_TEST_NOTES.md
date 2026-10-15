# Format-continue model — local test build

**Status:** Testable demo — **not** production-complete.

## What was trained

- **Checkpoint base:** fused Sotto + course-correction LoRA (`sotto-lc-ft-clean-fused`)
- **Continue-train:** format SFT LoRA (rank 16, all layers, 800 + 400 iters)
- **Data:** ~4k rows — Sotto public list-like + synthetic bullets/numbered/checklist + retention cleanup
- **Fused model:** `bench/polish_finetune/fused/sotto-format-sft-fused/`

## App install (side-by-side)

- **Stable:** `/Applications/MacWispr.app` (unchanged 1.2.3)
- **Test:** `/Applications/MacWispr-FormatTest.app` (LFM polish + format model, ad-hoc signed)

## How to test

1. Quit stable MacWispr if both fight for ⌥Space
2. Open **MacWispr-FormatTest**
3. Settings → Polish → **Local** (LFM path)
4. Dictate phrases like:
   - “camping list tent headlamp and snacks as bullets”
   - “onboarding create account verify email invite team as a numbered list”
   - “grab oat milk no wait almond milk”
5. Expect ~50–80 ms polish after STT; model is bundled (no download)

## Held-out qualitative results (read by agent)

| Family | Base (course only) | Format-continue |
|--------|-------------------:|----------------:|
| Format (bullets/numbered/checklist) | 0/6 | **5/6** |
| Course (simple) | 3/3 | 3/3 |
| Light cleanup | pass | pass |
| Prose (no force list) | pass | pass |

### Clear wins

- “camping trip … in bullet points” → proper `-` list
- “onboarding steps … numbered please” → 1–4 steps
- “jot down onions… as a list with dashes” → bullets
- Simple course-correction retained (Alice→Bob, ten→fifteen)

### Still broken / weak (do not call complete)

- **“as checkboxes”** sometimes ignored (stays prose)
- **Course + format together** often drops list:
  “pepperoni no wait margherita … as bullets” → drops pizza, no list
- **Dropped list items** on long steps (e.g. debug path lost “file an issue”)
- Hard course still weak (overnight→two-day, maple/elm) — same as pre-format base
- Odd tokens occasionally (“BQwen”)
- Checklist prefers `-` over `- [ ]`

## Not complete

Do not ship as 1.3.0 yet. Needs more course+format pairs, checkbox cues, and anti-drop item training.
