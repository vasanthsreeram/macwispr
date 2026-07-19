# GitHub Actions CI/CD

Automated **build + test** on every PR/push to `main`, and **signed + notarized releases** when a `v*` tag is pushed.

| Workflow | Trigger | Signing | Output |
|----------|---------|---------|--------|
| [`.github/workflows/ci.yml`](../.github/workflows/ci.yml) | PR / push → `main` | ad-hoc (no secrets) | artifact + self-test |
| [`.github/workflows/release.yml`](../.github/workflows/release.yml) | tag `v*` or manual dispatch | Developer ID + notarize | GitHub Release + Sparkle appcast |

**Cost:** `vasanthsreeram/macwispr` is a **public** repo — standard `macos-15` runners are **free**.

---

## One-time setup (Vasanth — repo owner)

Open the repo on GitHub → **Settings → Secrets and variables → Actions → New repository secret**.

### Required secrets

| Secret | What it is | How to create |
|--------|------------|---------------|
| `DEVELOPER_ID_CERTIFICATE_P12` | Developer ID Application cert | Keychain Access → export cert + private key as `.p12` → `base64 -i cert.p12 \| pbcopy` |
| `DEVELOPER_ID_CERTIFICATE_PASSWORD` | `.p12` export password | The password you chose when exporting |
| `APPLE_ID` | Apple ID email | Same as notarization Apple ID |
| `APPLE_TEAM_ID` | Team ID | `UTSTY3J6NS` |
| `APPLE_APP_PASSWORD` | App-specific password | [appleid.apple.com](https://appleid.apple.com) → App-Specific Passwords |
| `SPARKLE_PRIVATE_KEY` | Sparkle EdDSA private key | From Sparkle `generate_keys` (Keychain or export). **Never commit.** |

### Optional secrets

| Secret | When needed |
|--------|-------------|
| `MACWISPR_SIGN_IDENTITY` | Full string e.g. `Developer ID Application: Name (UTSTY3J6NS)` — auto-detected if omitted |
| `CLOUDFLARE_API_TOKEN` | Auto-deploy `website/appcast.xml` to fuckwisprflow.com |
| `CLOUDFLARE_ACCOUNT_ID` | Required by wrangler if using Cloudflare deploy step |

Local equivalent: `./scripts/setup-signing.sh` + Sparkle key in Keychain (see [SPARKLE.md](./SPARKLE.md)).

---

## Releasing a new version

1. Merge fixes to `main`
2. Bump `Info.plist` → `CFBundleShortVersionString` / `CFBundleVersion`
3. Commit, tag, push:

   ```bash
   git tag -a v1.2.4 -m "MacWispr 1.2.4"
   git push origin v1.2.4
   ```

4. **Release** workflow runs automatically:
   - builds `MacWispr.app` + `mlx.metallib`
   - Developer ID sign + Apple notarization
   - Sparkle-signs the zip
   - prepends `website/appcast.xml`
   - uploads zip + DMGs to GitHub Releases
   - deploys appcast (if Cloudflare secrets set)
   - commits appcast change back to `main`

5. Users with Sparkle get **Check for Updates → 1.2.4**

### Manual re-run

Actions → **Release** → **Run workflow** → enter an existing tag (e.g. `v1.2.4`).

---

## What Felix / contributors can do

- Open PRs with workflow changes
- Merge to `main` (with write access)
- **Cannot** add signing secrets unless repo admin — Vasanth must paste secrets once

---

## Troubleshooting

| Failure | Fix |
|---------|-----|
| `Metal compiler not found` | Workflow runs `xcodebuild -downloadComponent MetalToolchain` — re-run job |
| `no Developer ID Application identity` | Re-export `.p12` including private key; check `DEVELOPER_ID_CERTIFICATE_PASSWORD` |
| Notarization timeout | Apple can be slow; re-run. Check `APPLE_APP_PASSWORD` is app-specific, not account password |
| `sign_update not found` | Ensure `build-app.sh` completed (Sparkle artifact under `.build/artifacts`) |
| `appcast already contains version` | Bump version number — don't re-release the same `sparkle:version` |
| Cloudflare step skipped | Add `CLOUDFLARE_API_TOKEN` or deploy manually: `wrangler pages deploy website --project-name=fuckwisprflow` |

---

## Scripts (called by workflows)

| Script | Role |
|--------|------|
| `scripts/ci-import-signing.sh` | Import `.p12` into ephemeral CI keychain |
| `scripts/ci-sparkle-sign.sh` | `sign_update` → edSignature + length |
| `scripts/ci-update-appcast.sh` | Prepend new `<item>` to `website/appcast.xml` |
| `scripts/ci-publish-github-release.sh` | `gh release create/upload` for tag |

Existing release tooling (`build-app.sh`, `sign-and-notarize.sh`, `build-dmg.sh`) is unchanged.