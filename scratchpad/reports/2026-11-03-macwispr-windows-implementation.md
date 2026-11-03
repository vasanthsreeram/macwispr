# MacWispr Windows — implementation report

**Status: BLOCKED for publication, branch ready for review.** I built a Windows dictation app and
it passes build, self-test, end-to-end hotkey→paste and installer checks on a real Windows
machine (a GitHub-hosted `windows-2022` runner). It has **not** been tested with a real
microphone or on Windows 10/11 desktop, so I did not publish it, change the website, or
create a release. You stopped the local VM because it caused memory and swap pressure on this host.

Labels: **[M]** measured (tool output), **[I]** inferred, **[U]** unknown.

## Branch and commits
- Repo `vasanthsreeram/macwispr`, branch **`feat/windows-dictation`** (pushed). It is based on
  `origin/main` `c98fb15`, which I checked with `git ls-remote` at start [M]. I used a fresh clone at
  `/home/vasanth/projects/personal/macwispr/worktrees/windows-support`. I did not touch the dirty
  `.../macwispr/main` checkout or the MacBook [M].
- Commits: `3697cd7` app + build + CI · `4373bbd` remove committed bytecode, pytest path ·
  `fc5e961` bundle package metadata · `af39394` stdout/stderr for the windowed build ·
  `da23750` e2e race fix · plus a final commit with the rule-10 report and website draft patch.
- PR not opened: https://github.com/vasanthsreeram/macwispr/pull/new/feat/windows-dictation
- macOS app: no Swift, `Package.swift`, script or website file changed [M] (`git diff --stat origin/main`:
  only `windows/**`, `.github/workflows/windows.yml`, `.gitignore`, `scratchpad/**`). The macOS
  CI workflow triggers only on `main`, so I did not run it [M].

## What was built (`windows/`)
Python tray app, frozen with PyInstaller, with an Inno Setup per-user installer (no admin):
- Global **Alt+Space** through a `WH_KEYBOARD_LL` hook. It supports hold or toggle mode, swallows Space
  while the chord is active, and taps a mask key so Alt-release doesn't open menus.
- Mic capture through PortAudio (`sounddevice`), 16 kHz mono, capped at 10 minutes.
- Insertion: clipboard + `SendInput` Ctrl+V after the modifiers are released. It restores the previous text clipboard.
- Tray menu with status, mode, paste on/off, clipboard restore, sounds, history, data folder and quit.
  It also has local `history.jsonl`, a log, a single-instance mutex, and no telemetry.
- `--self-test`, `--transcribe-file`, and a hidden `--fake-mic <wav>` for machines without a mic.
- `.github/workflows/windows.yml`: build → self-test → e2e → silent install, then upload the artifacts.

## Model choice
- The Mac app ships Parakeet Redux on Photon/kestrel (`ModelCatalog.swift`) [M].
  kestrel has `win_amd64` wheels, but it needs torch plus native kernels [M]. Whether Redux runs on
  a plain Windows CPU is [U]. I did not test it because it would cost a large torch sidecar.
- Chosen: **Parakeet TDT 0.6B v3, int8 ONNX** (`istupakov/parakeet-tdt-0.6b-v3-onnx`) through
  `onnx-asr` 0.12.0 on ONNX Runtime CPU. It is the base model that Redux is derived from [I], covers the
  same languages [I], and needs no GPU.
- Cost: it downloads about 670 MB on first launch (640 MB on disk [M]), against about 180 MB for Redux. Peak RSS was about 1.4 GB on Linux [M].
- Accuracy and speed [M]: both bench clips transcribed correctly. On the Windows runner, a 10 s clip took 0.77–0.91 s and model load took 8.6 s.
  On this Linux host under swap pressure, the same clip took 1.4–1.7 s.
- Assumption: "change the model" means "use what runs on Windows". The Mac model is unchanged.

## Exact Windows tests
Environment: GitHub-hosted runner, image `windows-2022` 20261025.346.1, Microsoft Windows
Server 2022, Python 3.12.10 [M]. Passing run **41587259797**
(https://github.com/vasanthsreeram/macwispr/actions/runs/41587259797) [M]:
- Unit tests: 7/7 passed on Windows and Linux [M].
- PyInstaller build, zip and Inno Setup installer built [M]. Sizes: `MacWispr-0.1.0-windows-x64-setup.exe`
  41,086,295 B and `MacWispr-0.1.0-windows-x64.zip` 60,732,864 B. The CI log shows SHA-256 values `94CA95C8…` and `46E01AD6…`
  (full values are in the log; I did not check which hash belongs to which file).
- Self-test with the frozen exe [M]: clipboard round-trip ok, keyboard hook installed ok, model download
  and transcription ok with the correct text. Microphone **failed** with `PortAudioError: Error querying
  device -1`, because the runner has no audio input [M/I].
- End-to-end [M]: the test launched Notepad and `MacWispr.exe --fake-mic sample_10s_16k.wav` and held Alt+Space for
  10.5 s with SendInput. The full correct transcript was pasted into Notepad, with no leaked Space and history written.
  The log showed ready → recording → transcribing → "transcribed 10.0s of audio in 0.91s".
- Installer [M]: `/VERYSILENT` install to `%LOCALAPPDATA%\Programs\MacWispr`, and the installed exe runs `--version`.
- CI found and I fixed 2 real packaging bugs: missing `onnx-asr` metadata, and a crash in the windowed build when
  `stderr` is None.

Not tested [U]: real microphone capture or a human speaking, Windows 10/11 desktop, the tray menu
clicked by a person, SmartScreen behaviour for the unsigned exe, elevated target windows, non-US
keyboard layouts, antivirus false positives, and long dictations (>60 s chunking).

## Local VM attempt
No Windows VM existed. The Tailscale Windows nodes are tagged devices, mostly offline and not mine to change, so I did not use them.
I provisioned `dockurr/windows` (Windows 10 LTSC Evaluation, KVM, 6 GB RAM, ports bound to localhost)
as container `macwispr-win`. Setup reached "Installing Windows". At 13:49 the host was at about 31/32 GB swap, and
you stopped the container (exit 137). I have not restarted it.
**Leftovers (not deleted; your call):** the stopped container `macwispr-win`, image `dockurr/windows`,
and `~/vms/macwispr-win` (7.2 GB: ISO, partial disk, OEM script, a random VM password file `.pw`).
To remove them: `docker rm macwispr-win && rm -rf ~/vms/macwispr-win`.

## Website and release status
- Live https://fuckwisprflow.com/ matches `website/index.html` on `main` byte-for-byte [M]. **Unchanged.**
- **No** GitHub release, no R2 upload, no Pages deploy, no appcast change [M]. The CI artifact
  (`MacWispr-windows-da23750…`, 14-day retention) is the only build.
- I prepared a draft that is **not applied**: `scratchpad/windows-website-draft.patch` on the branch. It extends the R2 download
  function allow-list to `MacWispr-<v>-windows-x64(-setup.exe|.zip)`; a node check showed the old Mac names still match and
  `../`-style names are rejected [M]. It also adds a "Windows preview" chip and install block. In a local Chromium check, desktop and 390 px
  had no overflow or JS errors and the link scrolled to the block [M]. **Fix before use:** the heading hides under the sticky
  header, and the existing copy "Mac only", "No Windows builds. On purpose." and "Windows can wait outside" contradicts it.
  The ticker, OG/Twitter descriptions, FAQ JSON-LD and footer also need updating.

## Next action (to publish)
1. Test `MacWispr-0.1.0-windows-x64-setup.exe` from the CI artifact on a real Windows 10/11 PC with
   a mic: install, wait for the model, then dictate into Notepad, a browser and Word in hold and toggle modes.
2. If it passes: open a PR from `feat/windows-dictation` and merge it. Run `gh release create windows-v0.1.0 --prerelease`
   with the CI artifacts, which leaves macOS `latest` and the appcast untouched. Run `wrangler r2 object put macwispr-downloads/<file>` for each
   artifact, apply and finish the website patch, then run `wrangler pages deploy website --project-name=fuckwisprflow`.
   On this host `wrangler whoami` returned no account details, so Cloudflare access is [U]. `gh` is logged in [M].
3. Consider code signing (SmartScreen) and a lighter model later.

Timebox: started 13:30, finished about 14:10 SGT [M].
