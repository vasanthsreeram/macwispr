# MacWispr Windows — implementation report

**Status: BLOCKED for publication, branch ready for review.** I built a Windows dictation app and
it passes build, self-test, end-to-end hotkey→paste and installer checks on a real Windows
machine (a GitHub-hosted `windows-2022` runner). It has **not** been tested with a real
microphone or on Windows 10/11 desktop, so I did not publish it, deploy the website, or
create a release. The website changes are committed on the branch and ready to deploy, but they are **not live**.
You stopped the local VM because it caused memory and swap pressure on this host, and I have not restarted it.

Labels: **[M]** measured (tool output), **[I]** inferred, **[U]** unknown.

## Branch and commits
- Repo `vasanthsreeram/macwispr`, branch **`feat/windows-dictation`** (pushed). It is based on
  `origin/main` `c98fb15`, which I checked with `git ls-remote` at start [M]. I used a fresh clone at
  `/home/vasanth/projects/personal/macwispr/worktrees/windows-support`. I did not touch the dirty
  `.../macwispr/main` checkout or the MacBook [M].
- Commits: `3697cd7` app + build + CI · `4373bbd` remove committed bytecode, pytest path ·
  `fc5e961` bundle package metadata · `af39394` stdout/stderr for the windowed build ·
  `da23750` e2e race fix · `331709a` rule-10 report · `f68e46a` **website preparation**
  (unpublished) · plus a final commit that updates the rule-10 report.
- PR not opened: https://github.com/vasanthsreeram/macwispr/pull/new/feat/windows-dictation
- macOS app: no Swift, `Package.swift` or script file changed [M]. `git diff --stat origin/main` shows
  `windows/**`, `.github/workflows/windows.yml`, `.gitignore`, `scratchpad/**` and 6 `website/` files. The macOS
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
- **Not published [M]:** live https://fuckwisprflow.com/ still matches `origin/main:website/index.html`
  byte-for-byte. `/download/MacWispr-0.1.0-windows-x64-setup.exe` returns 404. GitHub Latest is still
  `v1.3.0`. There was no R2 upload, Pages deploy or appcast change. The branch only gets Windows CI,
  which builds artifacts and does not deploy. The CI artifact (`MacWispr-windows-da23750…`, 14-day retention) is the only build.
- **Prepared on the branch (`f68e46a`)**, ready to deploy after the live-mic test:
  - Mac-only copy replaced with "Mac + Windows preview" wording in: meta description and keywords,
    OG/Twitter text, JSON-LD (`operatingSystem`, description, the offline FAQ, and the "Does MacWispr support
    Windows?" FAQ, which now answers "Yes, in preview"), the ticker, the hero eyebrow, the comparison list, the Platform card
    ("Mac first. Windows is in preview."), the CTA note plus a "Windows preview" button, the footers on `/`, and the
    footer notes on `/why`, `/rnd` and `/leaderboard`. The "No Windows builds. On purpose." notes are removed. A grep for
    "mac only", "no windows" and "wait outside" across `website/**/*.html` finds nothing [M].
  - New "Install on Windows (x64)" block with 3 steps (installer link, SmartScreen, tray plus about 670 MB model, mic plus
    Alt+Space). The `/privacy` page gets a Windows section: no telemetry, CPU-only ASR, a one-time model download, and local
    history, settings and log in `%LOCALAPPDATA%\MacWispr`.
  - R2 download function: the allow-list now also accepts `MacWispr-<v>-windows-x64(-setup.exe|.zip)`. A node check shows the Mac
    names still match and `../` names are rejected [M].
  - **Sticky-header fix:** `<style>#install-windows { scroll-margin-top: 6.5rem; }</style>` is inline in
    `index.html`, because `styles.v7.css` is cached `immutable` for a year (`_headers`).
- **Browser tests [M]** (Playwright plus system Chromium against a local static server, at 1280×900 and 390×844):
  - Clicking the hero "Windows (preview)" chip and clicking the CTA "Windows preview" button both land on the section.
    The kicker sits below the header's bottom edge: 104 px vs 68 px on desktop and 82 px vs 69 px on mobile. The
    installer href is correct.
  - No horizontal overflow on `/`, `/why/`, `/rnd/`, `/leaderboard/` or `/privacy/`. All return 200 and there are no JS page errors.
  - I checked screenshots of the Windows section, the Platform card and the privacy section. The first render broke
    "More info → Run anyway" into block headings, because the step cards style `<strong>` as headings. I replaced it with quoted text and re-checked.
  - Console noise that also occurs on `main` and comes from the local server: the leaderboard API's CORS allows only `https://fuckwisprflow.com`.
    `/leaderboard/` requests `styles.v8.css`, which my local server 404s, but production serves it with 200 [M].
- Not tested [U]: Cloudflare Pages Functions locally (no `wrangler pages dev` run) and real downloads through R2.

## Next action (to publish)
1. Test `MacWispr-0.1.0-windows-x64-setup.exe` from the CI artifact on a real Windows 10/11 PC with
   a mic: install, wait for the model, then dictate into Notepad, a browser and Word in hold and toggle modes.
2. If it passes: open a PR from `feat/windows-dictation` and merge it. Run `gh release create windows-v0.1.0 --prerelease`
   with the CI artifacts, which leaves macOS `latest` and the appcast untouched. Run `wrangler r2 object put macwispr-downloads/<file>` for each
   artifact, merge the branch's website changes, then run `wrangler pages deploy website --project-name=fuckwisprflow`.
   Afterwards, check that `/download/MacWispr-0.1.0-windows-x64-setup.exe` returns 200 on production.
   On this host `wrangler whoami` returned no account details, so Cloudflare access is [U]. `gh` is logged in [M].
3. Consider code signing (SmartScreen) and a lighter model later.

Suggested follow-ups (outside scope, not fixed):
- On mobile, the existing Mac `#install` heading sits slightly under the sticky header (title top 61 px vs header bottom
  69 px, same as on `main`) [M].
- The `/privacy` local row still says "ASR runs on Apple Silicon via MLX"; 1.3.0 uses Photon.
- `website-macwispr/` (macwispr.lintware.com) and `PRIVACY.md` still describe the product as Mac only.

Timebox: started 13:30. The first pass finished about 14:10 SGT, and the website preparation pass finished about 14:15 SGT [M].


---

# Windows audio-capture verification (VERIFICATION-BRIEF.md)

**Status: real capture verified end to end on Windows. CI run 41591734759 is red on one strict
accuracy gate** (toggle WER 17.4% against a 15% limit; details below). I did not loosen the gate: that is a test-definition
choice for the parent. No VM was started on lintlabs-1. Nothing was released, merged or deployed.
Time: 14:13–14:52 SGT (45-minute timebox).

Labels: **[M]** measured, **[I]** inferred, **[U]** unknown.

## Endpoint and driver [M]
- Disposable GitHub runner: image `windows-2022` 20261025.346.1, Windows Server 2022.
- **VB-Audio Virtual Cable** 3.3.1.7 (`VBCABLE_Driver_Pack45.zip` from `download.vb-audio.com`, SHA-256 pinned
  `b950e39f…16bfb`). The catalog signature is **Valid**: signer *Microsoft Windows Hardware Compatibility
  Publisher*, issuer *Microsoft Windows Third Party Component CA 2014*. No signature bypass was used. The signer
  certificate goes into TrustedPublisher only to skip the install prompt.
- Install path: root device `VBAudioVACWDM` created with the SetupAPI calls `devcon install` uses
  (`windows/tests/ci_root_device.py`). Result: "reboot required: False". The Audiosrv and AudioEndpointBuilder
  services had to be enabled, because Server ships them disabled.
- Endpoints created: **CABLE Output (VB-Audio Virtual Cable)** (recording) plus the "CABLE In 16 Ch" / "Speakers
  (VB-Audio Virtual Cable)" render endpoints. Test audio is played to the default output and comes back on the default input.
- Licensing: VB-CABLE is donationware under VB-Audio's own licence. It is used only on the throwaway CI runner and is not shipped [I].

## Native format and how the app opens the stream [M]
- The app's stream: PortAudio host API **MME**, device `CABLE Output (VB-Audio Virtual `, native rate **44100 Hz**,
  **16** max input channels. The app opens it at **16000 Hz, 1 channel, latency 0.026 s**, and the Windows audio engine converts.
- Per host API (`capture_probe.json`): MME and DirectSound open at 16 kHz mono, at the native rate mono, and at the native
  format. WASAPI (native 48 kHz, 2 ch) **rejects 16 kHz** ("Invalid sample rate") but opens at native. WDM-KS fails in
  blocking mode. The app uses the default MME device, so it is unaffected. WASAPI is a limitation if the device is ever made selectable.

## Bugs found by real capture, and fixes
1. **Microphone privacy switch off gave a cryptic error.** The runner's user setting is
   `HKCU\...\CapabilityAccessManager\ConsentStore\microphone = Deny` (HKLM Allow, NonPackaged Allow). The stream open then
   fails with `Unanticipated host error [PaErrorCode -9999] [MME error 1]` at 16 kHz **and** at the native rate.
   - First I tried opening at the native rate and resampling (`b95cc5a`). The probe showed that failed the same way,
     so I **reverted it** (`a94a169`).
   - Fix: detect the Deny switches and raise *"Windows is blocking the microphone. Open Settings > Privacy > Microphone
     and turn on microphone access and 'Let desktop apps access your microphone'."* (`a94a169`).
   - Because the tray status falls back to Ready after an error, I also show the error as a tray notification (`5a45adf`).
   - CI proves the blocked case before turning access on: the self-test reports this message, and the installed app
     logs it on Alt+Space with nothing pasted (`e2e_microphone_denied.json`) [M]. I did not see the notification itself [U].
2. **Empty transcript in hold mode.**
   - Seen in run 41589580793: 11.2 s captured (peak 0.565, rms 0.118, status ok) gave "0 chars" and nothing was pasted.
   - Reproduced offline with the captured WAV and with the clean source clip. Parakeet int8 ONNX returns `''` after 0.3, 0.6, 0.7
     and 1.1 s of leading digital silence; the other 9 offsets work.
   - Rejected: dither 1e-5 left it failing, and 1e-4 fixed the offset grid but still failed on the captured WAV and hallucinated "Yeah." on silence.
   - **Fix (`ed96cad`):** decode only Silero-VAD speech segments (`onnx-asr` `with_vad`, `istupakov/silero-vad-onnx`,
     2.3 MB, downloaded with the model). Max segment is 30 s, which replaces the fixed 60 s chunking.
   - Offline result: all 26 offset cases and the captured WAV transcribe, 3 s of silence gives `''`, and the 68.8 s clip
     keeps its phrase counts [M].
   - Side effect [M]: VAD sometimes turns the clip's first word "But" into "May but" or "Maybe", and it changes proper nouns. On the clean
     files the VAD path scores 3.2–9.7% (sample_10s) and 13.0% (speech_12s) WER against the old no-VAD transcripts.
3. The probe's round-trip metric failed once on a 12 ms buffer discontinuity at about 6 s (lag 0.789 → 0.801 s, capture status
   ok) [M]. The likely cause is the test's own playback underrunning [I]. The probe now plays with high latency, records
   playback and capture status, and reports per-second alignment (`05cef33`).

## Final CI proof: run 41591734759, commit `05cef33` [M]
https://github.com/vasanthsreeram/macwispr/actions/runs/41591734759. Steps: cable install, then build with unit tests, then
self-test with the mic **blocked** (clear error; clipboard, hook and model ok), then silent install, then the installed app with the mic
blocked (clear error, nothing pasted), then turn on mic access (`Allow / desktop apps: Allow`), then a self-test where **all checks
ok, including a 1 s capture**, then the probe, then end-to-end runs with the **installed app started normally** (no flags, default data folder, default mic):

| Scenario | Speech | Captured | Pasted into Notepad | WER vs file transcript | Gate |
|---|---|---|---|---|---|
| Round trip (app `Recorder`) | 10.0 s | 11.05 s, lag 0.788 s, corr **0.962**, gain 0.988, every second aligned, capture/playback status clean | n/a | n/a | pass |
| Hold | 10.0 s | 11.21 s, peak 0.566, status ok | "May but When a human drops in the world, … 21st century." | 3.2% | pass |
| Toggle | 9.57 s | 10.92 s, peak 0.726, status ok | "Hello. This is a dictation latency benchmark for Mac Whisper. … Apple Silicon." | **17.4%** | **fail (≤15%)** |
| Hold, 68.8 s | 68.7 s | 69.89 s, status ok; transcribed in 14.9 s | 1117 chars; springboard 4/4, benchmark 3/3 | 8.8% | pass |

The toggle text differs only in proper nouns and punctuation ("Mac Whisper", "three", "Nemotron's"). The same VAD path scores 13.0% on
the clean file, so capture adds about one word [M]. Options for the parent: (a) use reference transcripts from the shipped decode
path, so the gate measures capture fidelity; (b) use human-written ground truth with a model-appropriate limit; or (c) accept
as is. I did not apply any of them.

Artifacts (run 41591734759, unsigned): `MacWispr-0.1.0-windows-x64-setup.exe` 41,089,177 B, SHA-256
`61a8c7eaaccaa476f3d347b650f857cf9b2e5be0ac71c1a55a31794aa29fc573`; `MacWispr-0.1.0-windows-x64.zip` 60,736,764 B,
`9e9b5eeea758d746cdec9effff5eaa7e03b1a281c0d805cdbdb5b673eedf80ce`; artifact `MacWispr-windows-05cef33…`
digest `sha256:ed74f996c42b06b287263dbd657f9a43e145e0f8f4a19359779362580d5e3721` (14-day retention).
I downloaded the files and hashed them locally; the hashes match the CI log.

Evidence saved in `evidence/`:
- `run-41591734759/`: self-tests (blocked and allowed), `capture_probe.json`, the 4 `e2e_*.json`, and `app.log`. The log only contains
  Hugging Face warnings and no secrets.
- `run-41589580793/`: the failing hold result before the fix, and the captured WAV that gave the empty transcript.

## Commits this pass (branch `feat/windows-dictation`, pushed; draft PR #31 is the parent's)
`20dd2d7` capture logging · `534071e` VB-CABLE CI and removal of `--fake-mic` · `b95cc5a` native-rate try · `a94a169` its revert, plus
the clear privacy error · `5a45adf` error notification · `7003c09` blocked→allowed CI flow · `ed96cad` Silero VAD · `05cef33` probe
diagnostics. History note: `a94a169` adds a unit test that only passes from `5a45adf` onward.

## Windows client limitations (current)
- Only the default recording device is used; there is no picker. WASAPI-only setups at 16 kHz would fail if a device choice is added.
- The first run needs microphone access turned on in Windows privacy settings. The app explains this but does not open Settings itself.
- Not code-signed (SmartScreen warning). The first launch downloads about 672 MB (Parakeet plus VAD).
- VAD can drop or alter the first word, and proper nouns vary. No live partials, custom vocabulary, hotkey rebinding,
  auto-update, meetings or CLI.
- Not verified [U]: a physical microphone with a human voice, Windows 10/11 client editions (only Server 2022 was tested),
  per-user privacy prompts on client Windows, elevated target windows, and the notification balloon itself.

## Resume
Pick a gate option (a/b/c) in `windows/tests/e2e_capture.py` (`REF` and the 0.15 limit), push, then run
`gh run watch $(gh run list -R vasanthsreeram/macwispr --branch feat/windows-dictation --workflow Windows --limit 1 --json databaseId -q '.[0].databaseId') -R vasanthsreeram/macwispr`.
