# Claude / coding agents

Read **[AGENTS.md](./AGENTS.md)** first — it is the canonical agent guide for MacWispr.

Quick pointers:

- Local test before release: `./scripts/install.sh` then try ⌥Space
- Privacy: opt-in telemetry only; never send transcripts/audio (`PRIVACY.md`, `Sources/Telemetry.swift`)
- HUD: glowing dot + timer only (`ListeningHUDController.swift`)
- Soft chimes: low volume in `FeedbackSounds.swift`
- Sparkle: `website/appcast.xml` + [docs/SPARKLE.md](docs/SPARKLE.md)
- Architecture notes: [docs/context/](docs/context/)
- Model UI names: **Qwen 0.6B/1.7B (En + Asian)**, **Parakeet v3 (En + EU)**; chip says **Local** (`ASRModelSize.swift`)
- **Stable:** **1.2.8** = GitHub Latest + Sparkle (live waveform HUD + mid-recording mic rebind) — [RELEASE_1.2.8.md](docs/context/RELEASE_1.2.8.md) (never launch repo `dist/MacWispr.app` over `/Applications`)
- Stay on Swift (not Rust/Zig/Bun): [docs/context/LANGUAGE_STACK.md](docs/context/LANGUAGE_STACK.md)

## Polish model (post-training)

The on-device dictation-polish LLM (Qwen3.5-0.8B, 4-bit MLX) has its own workstream:

- **Status & playbook:** [docs/context/post-training/POST_TRAINING_STATUS.md](docs/context/post-training/POST_TRAINING_STATUS.md) — read this first for the polish model.
- **Cross-model benchmarks + cost:** [bench/polish_posttrain/BENCHMARK_RESULTS.md](bench/polish_posttrain/BENCHMARK_RESULTS.md) (Sonnet/Haiku/Gemini Flash+Lite/Grok/gpt-oss vs our local model on fact retention).
- **Progress log:** [docs/context/post-training/plans/EXECUTION-CHECKLIST.md](docs/context/post-training/plans/EXECUTION-CHECKLIST.md)
- Current ship candidate: **v4-dpo100 4-bit** (80% structure, 93.5% fact retention) — staged, **not pushed** (needs user approval + vibe test).
- Two held-out evals: `ood_eval_set.jsonl` (structure), `meaning_eval_set.jsonl` (fact retention). Shared scorers = RL rewards: `polish_verifier.py`, `fact_heuristic.py`, `meaning_verifier.py`.
- Training runs on Mac Studio `hcserver@100.64.0.4`. Data gen via `gen_distill.py` (agy=free Gemini 3.6 Flash / API=paid Flash-Lite).
- RL direction: **Rejection-sampling FT + DPO** (GRPO demoted after NaN-collapse); LLM-as-judge (Flash-Lite) for offline DPO ranking only.
- **API keys (Gemini/xAI) are env-var only — NEVER commit; secret-scan before every commit.**
