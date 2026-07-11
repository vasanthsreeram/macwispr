# Language & stack choice

**Decision: stay on Swift.** Do not rewrite MacWispr in Rust, Zig, Bun/JS, or similar for “lighter / more efficient” alone.

Last updated: 2026-07-12

## Why size and RAM are not language-bound

MacWispr is a thin controller around Apple frameworks + on-device ASR. Weight is dominated by **MLX/Metal** and **model weights**, not the Swift app shell.

| Component | Approx size | Changed by language rewrite? |
|-----------|-------------|------------------------------|
| App binary | ~39 MB | Partially |
| Metallibs (`mlx` + `default`) | ~200 MB | No (if keep MLX) |
| Model 0.6B 8-bit | ~1 GB | No |
| Model 1.7B 8-bit | ~2.3 GB | No |
| Ship zip | ~100 MB | Small gain only if MLX stays |
| Peak RAM while dictating | ~1–3+ GB | No (model-bound) |

## Language comparison (this product)

| | **Swift (current)** | **Rust** | **Zig** | **Bun / JS** |
|--|---------------------|----------|---------|--------------|
| **Fit** | Best | Possible, painful | Poor ecosystem | Bad fit |
| **Download size** | Baseline | ~5–20% smaller if MLX stays | Similar to Rust | Often larger |
| **Idle RAM (no model)** | Baseline | −20–80 MB possible | Similar / slightly less | Usually worse |
| **Peak RAM (dictating)** | Model-bound | ~Same | ~Same | ~Same or worse |
| **Dictation latency** | Model/Metal-bound | ~0 gain | ~0 gain | ~0 gain |
| **Menu bar / AX / hotkey** | Native AppKit | Hard (bindings) | Harder | Needs native sidecar |
| **MLX / Qwen path** | Mature (`speech-swift`) | Less mature | Weak | Via native only |
| **Rewrite cost** | — | High (months) | Very high | High + wrong tool |

## What actually makes the app lighter

Ranked by impact (prefer these over a rewrite):

1. Model choice / quantization (0.6B vs 1.7B)
2. Unload MLX / Core ML when idle or when switching models
3. Slim metallib packaging (if feasible)
4. Core ML / ANE vs full MLX where quality allows
5. Optional cloud-only / no-MLX build
6. Language rewrite — **small shell gains only**

## Verdict

| Goal | Choice |
|------|--------|
| Ship macOS dictation with MLX + AX + Sparkle | **Swift** |
| Theoretical rewrite-only win | Modest binary/idle shell only; not half the app |
| Real efficiency work | Models, unload, packaging — not Rust/Zig/Bun |

**Out of scope unless explicitly requested:** full rewrite in another language.
