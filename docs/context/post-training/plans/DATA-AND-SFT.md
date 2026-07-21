# Plan: data + SFT discipline

---

## Two-pass synthetic (keep)

| Pass | Temp | Output |
|------|------|--------|
| Seeds | ~1.15 | Messy `raw` only |
| Labels | ~0.1 | Gold `clean` only |

Auth: Grok OAuth (`~/.grok/auth.json` → `api.x.ai`). Batches ~25–50.

---

## Structure tags (current)

| Tag | Intent |
|-----|--------|
| multi_list | ≥2 separate lists |
| mixed_styles | Numbered + bullets/checklist |
| format_numbered / bullets / checklist / mixed | Single-structure |
| format_email / paragraphs / sectioned_notes | Doc shapes |
| labeled_fields | `Label: value` |
| course_plus_format | Correct then list |
| preserve_question / prose / course / light | Safety + cleanup |

---

## Hard style_ok (enforce)

| Tag | Gold must satisfy |
|-----|-------------------|
| multi_list | ≥2 blank-separated list blocks **or** ≥2 headings each with items |
| mixed_styles | `(?m)^\d+\.` **and** (`- ` or `- [ ]`) |
| format_numbered | `1.` present; no checklist |
| format_bullets | `- ` not numbers/checks |
| format_checklist | `- [ ]` |
| labeled_fields | ≥3 `Label: value` lines |
| preserve_question | ends `?`; no answer openers |

Upsample multi_list / mixed / numbered until ≥25–30% of list-bearing train rows use numbers where appropriate.

---

## SFT recipe (structure continue)

| Knob | Value |
|------|--------|
| Init | `fused/qwen35-08b-polish-structure` or enum |
| Type | full SFT (`mlx_lm.lora --fine-tune-type full`) |
| LR | 2e-6–3e-6 |
| Max seq | 1024 |
| Iters | 300–600 depending on data delta |
| Retain | light / prose / question mix so format doesn’t eat cleanup |

Script: `~/.cache/macwispr-minicpm-bench/scripts/train_structure_sft.sh`

---

## Anti-patterns

- One LLM call for raw+clean  
- Merging chat MiniCPM legacy as majority of train  
- Training on the fixed 20 offline eval prompts  
- Shipping bf16 as default when product is 4-bit path  
