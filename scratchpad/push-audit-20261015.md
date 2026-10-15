# MacWispr push audit — 2026-10-15

Unit: MacWispr outstanding-work preservation. Operator: Claude agent on lintlabs-1 (server), driving the
MacBook through the Mac mini (`ssh -p 2422 admin@100.64.0.2` → `ssh macbook`).
Labels: **[measured]** = command output seen; **[inferred]** = deduced from measured facts; **[guess]** = unverified.

## Result

All publishable outstanding work and unique history are now on GitHub (`vasanthsreeram/macwispr`, public)
under one work branch and three archive branches. `main` was not changed locally or on the remote. No force
push, no tag, no release, no deploy. The installed app (`/Applications/MacWispr.app`, PID 36838) was not
touched. **[measured]**

## Remote refs after push (`git ls-remote origin`, from the Mac mini)

| Ref | Hash | Content |
|---|---|---|
| `wip/2026-10-15-outstanding-work` | child of `9068a26` (this report's commit; see LOG.md for final tip) | 7 commits on top of `main` 99553b7 |
| `archive/leaderboard-beta-2026-07-23` | `f7ce1275adbef92762ecd604d0aefde68986dc6a` | local `backup/leaderboard-beta-2026-07-23` (21 commits not previously on origin) |
| `archive/stash-parakeet-redux-wip-20261014` | `a064b0de6978042d3b1233ba14c8f82467441d72` | dropped stash "parakeet-redux-wip" (Swift source, 4 files) |
| `archive/stash-wip-during-beta-strip-20260723` | `1a13e9128c2a95caf35840ada0ee4b1a9972a7bb` | tracked snapshot of dropped stash `4f35f75`, re-parented on `af2157f` |
| `main` | `99553b7248d4637b800021b59594edaaa3817136` | unchanged |
| `release/1.3.0-redux` | `a4b8312…` | unchanged |
| `feat/leaderboard-1.2.9` | `fc847c6…` | unchanged |
| `fix/notarize-dmg` | `e5176d6…` | unchanged |
| `beta/1.2.4-beta.2-live-partials` | `4bcfc29…` | unchanged |

Push output: four `* [new branch]` lines, exit 0. **[measured]**

### Commits on `wip/2026-10-15-outstanding-work` (base `99553b7`)

| Commit | Subject | Files |
|---|---|---|
| `075bd15` | bench: ASR gate harness and full-suite benchmark | 13 |
| `14bb9fe` | feat: meetings, macwispr CLI/MCP agent access, Redux MLX sidecar, UI refresh | 45 |
| `1e0f382` | brand: refreshed logo assets and generator | 7 |
| `d4dab99` | bench(polish): fine-tune and post-training scripts | 18 |
| `c5ec852` | chore: Sparkle local test script and website styles.v9.css | 2 |
| `9068a26` | docs(scratchpad): Redux MLX port evidence and handoff notes | 67 |
| (next) | docs(scratchpad): push audit report | 1 |

Every committed file was byte-compared (`cmp`) against the local working tree: 0 mismatches. **[measured]**
The app changes in `AppState.swift`, `SettingsView.swift` and similar files mix several features. They are
committed as one feature commit rather than split by hunk. **[measured]**

## How it was done

- Coordination: no process held repo files open, the last write was at 21:50 SGT and the audit started at 22:35.
  The only later change was `GTM/tools/DemoStudio/.git/index`, which this audit's own `git status` refreshed.
  The old verification surface 1455 was closed by the user. **[measured]**
- Commits were made in a separate worktree (`/private/tmp/mw-publish-20261015`, branch
  `wip/2026-10-15-outstanding-work`) from a file list. The user's checkout `/Users/vas/Documents/lintlabs/macwispr`
  is still on `main` 99553b7 with the same 36 modified and 446 untracked paths. **[measured]**
- The MacBook `gh` token is invalid. The refs were sent as a git bundle (sha256
  `d2e4b16e222a2ff98baad0ac415e0f8308960582f30682dd770e295ec16d8262`, same hash on both machines) to a fresh
  bare clone on the Mac mini, then pushed with the mini's `gh` credential helper. No token was copied or printed.
  **[measured]**
- Before the push, a scan of all new objects found no blob over 2 MB, no excluded path, and no secret pattern
  (`sk-`, `xai-`, `ghp_`, `gho_`, `hf_`, `AIza`, private-key headers, `sb_secret_`). **[measured]**

## Kept local (not published)

Full list with size, SHA-256 and reason for each file: `scratchpad/local-only-manifest-20261015.tsv` in the
MacBook checkout (local only, 330 entries, 925,939,683 bytes). **[measured]**

| Category | Files | Reason |
|---|---|---|
| `GTM/` | 179 + nested clone | `GTM/ACCESS.md` calls it a "gitignored war room". It holds logged-in account session details, unpublished launch drafts and media. The repo is public. |
| `GTM/tools/DemoStudio/` | 1 dir | Third-party clone (`LucaXav/DemoStudio`, clean at `a166430`) |
| `bench/polish_finetune/{adapters,fused}/` | 60 | Model weights (largest 244 MB) |
| `bench/redux_mlx/` | 33 | Redux MLX runtime code. Its README and `build-app.sh` say runtime redistribution rights are unresolved. The HF release deliberately excluded it. |
| Training/eval datasets (`bench/polish_finetune/data/`, `bench/polish_posttrain/data/`, `sft_train_pool.jsonl`, `ood_eval_set_v2.jsonl`) | 24 | Some contain real dictation (for example cmux/LMux phrases from the owner's own use) |
| `bench/polish_posttrain/results/*.json` | 8 | Per-item model outputs on that eval data (`.md` summary published) |
| `bench/clips/old_barag_*` | 8 | Private voice recordings |
| `__pycache__/` | 11 | Bytecode |
| `sparkle-test/` | 3 | Local Sparkle test artifact (zip symlink, signature output) |
| `scratchpad/redux-mlx/native-ui-mlx/ui-{history,home}.png` | 2 | Show real dictation history and personal usage stats |
| Ignored areas | — | `dist/`, `.build/`, `bench/results/redux_mlx/*` (1.4 GB weights/results), `bench/data/`, signing env |

## History audit

| Item | Finding | Action |
|---|---|---|
| Worktree `beta/1.2.4-beta.2-live-partials` (`06c5648`, prunable, dir missing) | 90 commits not on origin, but all 90 trees exist on origin (same subjects). The tip tree equals origin `4bcfc29`. This is a message-only rewrite. **[measured]** | Not pushed: no unique content. **[inferred]** |
| Worktree `release-128` (detached `5668400`, prunable, dir missing) | Contained in `backup/pre-strip-claude-attribution`. 97/106 trees on origin; the other 9 are covered by `backup/leaderboard-beta-2026-07-23`. **[measured]** | Not pushed separately |
| `backup/pre-strip-claude-attribution` (`b76d048`) | 112 commits; 97 trees on origin, remaining 15 covered by the leaderboard backup. 17 messages carry Claude attribution, which the owner stripped from published history. **[measured]** | Not pushed. Pushing it would republish the stripped attribution with no content gain. **[inferred]** |
| `backup/leaderboard-beta-2026-07-23` (`f7ce127`) | 21 commits, 0 trees on origin, no attribution lines, no secret patterns. Its datasets are template-synthetic (`gen_fact_sft.py`). **[measured]** | Pushed as `archive/leaderboard-beta-2026-07-23` |
| Dropped stash `a064b0d` "parakeet-redux-wip" (2026-10-14) | 4 Swift files, all differ from current main and worktree. **[measured]** | Pushed as `archive/stash-parakeet-redux-wip-20261014` |
| Dropped stash `4f35f75` "wip during beta strip" (+ untracked parent `9b0569c`) | Tracked changes: polish scripts + website tweaks. Its base `b76d048` is pre-strip, with the same tree as `af2157f`. All 38 untracked files are identical to the current working tree. **[measured]** | New commit `1a13e91` with the identical tree on parent `af2157f`, pushed as `archive/stash-wip-during-beta-strip-20260723`. The untracked parent is not pushed (contains a dataset). |
| Dropped stash `d7087aa` "wip2 polish bench tracked" | Same changes as `4f35f75` minus the website/README edits, on the pre-strip base. **[measured]** | Covered by `1a13e91` |
| Other branches, tags (16) | `feat/leaderboard-1.2.9` and `release/1.3.0-redux` already match origin. All 16 tags exist on origin. No `git stash list` entries. No reflog-only commits. **[measured]** | None |

Pre-strip commits reachable from any pushed branch: 0. **[measured]**

Local refs added (MacBook): `wip/2026-10-15-outstanding-work`, `archive/leaderboard-beta-2026-07-23`,
`archive/stash-parakeet-redux-wip-20261014`, `archive/stash-wip-during-beta-strip-20260723` (also protects the
dropped stashes from garbage collection). Nothing was deleted. The two prunable worktree entries were left in place.

## Checks on committed code (in the worktree, on the MacBook)

| Check | Result |
|---|---|
| `swift build --product MacWispr` | First clean build printed `Build complete! (125.73 sec)` but exited 1, with no `error:` line in the captured tail. An incremental rebuild exited 0. **[measured]** |
| `swift build --product MacWisprCLI` | Exit 0 **[measured]** |
| `swift test` | 53 XCTest tests, 0 failures (includes `ReduxRuntimeConfigurationTests` 8/8 and `MeetingTests`). Exit 0. **[measured]** |
| Python syntax (`ast.parse`, 11 committed files) | All OK **[measured]** |
| Shell syntax (`bash -n`, 13 committed scripts) | 12 OK. `bench/bench_full.sh` fails (see below). **[measured]** |
| CI `build-app.sh` + `--self-test` | Not run. AGENTS.md says not to launch repo-built bundles, because LaunchServices can prefer them over `/Applications`. CI only runs on `main` push or PRs to `main`, and none were made. |

Preexisting failures in the recovered work (committed unchanged; not fixed, per scope):

- `bench/bench_full.sh` line 32 opens two heredocs with the same `PY` delimiter but has one body, so bash reports
  `syntax error: unexpected end of file`. **[measured]**
- `bench/bench_full.sh` builds `--product BenchFull`, but no branch's `Package.swift` defines a `BenchFull` target
  (`BenchFull/main.swift` is standalone). **[measured]**

## Remaining blockers and owner decisions

1. **Merge to `main`** was not done. The work branch is a WIP snapshot that has not been release-verified. Open a PR from `wip/2026-10-15-outstanding-work` when ready. That will run CI.
2. **Redux MLX runtime code** (`bench/redux_mlx/`) stays local until runtime redistribution rights are reviewed. The committed `build-app.sh` flag `MACWISPR_EXPERIMENTAL_REDUX_MLX=1` copies from that directory, so it works only in the local checkout.
3. **GTM war room** stays local. If the owner wants it versioned, use a private repo.
4. **Datasets with real dictation** stay local. They could be published after scrubbing.
5. The MacBook `gh` token is invalid (`gh auth status`: "The token in default is invalid"). Re-authenticate it to push directly from the laptop.
6. Suggested follow-ups (not done): fix `bench/bench_full.sh`; add a `.gitignore` for `GTM/`, `sparkle-test/` and the dataset/weight paths so they cannot be published by accident; run `git worktree prune` for the two stale entries.

## Resume / verify

```bash
ssh -p 2422 admin@100.64.0.2 'git ls-remote https://github.com/vasanthsreeram/macwispr.git "refs/heads/*"'
```
