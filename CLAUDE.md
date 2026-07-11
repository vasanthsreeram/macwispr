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
- Stay on Swift (not Rust/Zig/Bun): [docs/context/LANGUAGE_STACK.md](docs/context/LANGUAGE_STACK.md)
