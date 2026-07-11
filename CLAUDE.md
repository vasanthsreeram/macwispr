# Claude / coding agents

Read **[AGENTS.md](./AGENTS.md)** first — it is the canonical agent guide for MacWispr.

Quick pointers:

- Local test before release: `./scripts/install.sh` then try ⌥Space
- Privacy: opt-in telemetry only; never send transcripts/audio (`PRIVACY.md`, `Sources/Telemetry.swift`)
- HUD: glowing dot + timer only (`ListeningHUDController.swift`)
- Soft chimes: low volume in `FeedbackSounds.swift`
- Sparkle: `website/appcast.xml` + [docs/SPARKLE.md](docs/SPARKLE.md)
- Architecture notes: [docs/context/](docs/context/)
