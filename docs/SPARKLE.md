# Sparkle auto-updates

MacWispr uses [Sparkle](https://sparkle-project.org/) so users can **Check for Updates…** without manually downloading a DMG from GitHub.

| Piece | Where |
|-------|--------|
| Framework | SPM dependency `https://github.com/sparkle-project/Sparkle` |
| Feed URL | `Info.plist` → `SUFeedURL` = `https://fuckwisprflow.com/appcast.xml` |
| Public EdDSA key | `Info.plist` → `SUPublicEDKey` |
| Private EdDSA key | **Never commit.** Keychain / secrets manager only |
| Appcast | `website/appcast.xml` → deploy to fuckwisprflow.com |
| Update zip | GitHub Releases: `MacWispr-X.Y.Z-macos-arm64.zip` |

```
MacWispr.app (Sparkle + public key)
        │
        ▼  fetches
https://fuckwisprflow.com/appcast.xml
        │
        ▼  points at
https://github.com/vasanthsreeram/macwispr/releases/download/vX.Y.Z/MacWispr-X.Y.Z-macos-arm64.zip
        │
        ▼
Sparkle downloads zip, verifies EdDSA signature, replaces app, relaunches
```

## One-time: generate keys

Sparkle tools ship with the SPM artifact (after `swift build` / package resolve):

```bash
# Path may vary by platform triple / Sparkle version:
SPARKLE_BIN="$(find .build/artifacts -type f -name generate_keys 2>/dev/null | head -1)"
# Or download a Sparkle release and use its bin/ folder.

"$SPARKLE_BIN"   # generate_keys
```

- **Public key** (base64) → replace the `PLACEHOLDER_…` value of `SUPublicEDKey` in `Info.plist`.
- **Private key** → stays in the Mac Keychain by default, or export to a secrets store.  
  **Do not commit the private key, `.pem`, or any `ed25519` secret files.**

You can re-print the public key later with the same tool if the private key is still in Keychain.

## Per-release flow

1. **Build** the app and zip (existing tooling):

   ```bash
   export MACWISPR_VERSION=1.2.2
   ./scripts/build-app.sh
   # produces dist/MacWispr-1.2.2-macos-arm64.zip
   ```

   Prefer **Developer ID + notarization** for production so Accessibility TCC survives updates — see [context/SIGNING.md](./context/SIGNING.md).

2. **Sign the zip** with Sparkle’s private key:

   ```bash
   SIGN_UPDATE="$(find .build/artifacts -type f -name sign_update 2>/dev/null | head -1)"
   "$SIGN_UPDATE" dist/MacWispr-1.2.2-macos-arm64.zip
   # prints: sparkle:edSignature="…" and length=…
   ```

3. **Update the appcast** (`website/appcast.xml`):

   - New `<item>` with `sparkle:version` / `sparkle:shortVersionString` matching `CFBundleVersion`
   - `enclosure` `url` using the GitHub Releases pattern above
   - `length` and `sparkle:edSignature` from `sign_update`
   - Optional HTML/markdown release notes in `<description>` or `sparkle:releaseNotesLink`

   Or regenerate with Sparkle’s `generate_appcast` against a folder of release zips.

4. **Publish binary** to GitHub Releases (existing):

   ```bash
   ./scripts/release.sh v1.2.2
   ```

5. **Deploy appcast** so `https://fuckwisprflow.com/appcast.xml` serves the updated feed (static host / Cloudflare Pages — only the small XML, not the multi-hundred-MB zip).

## In-app UI

- Menu bar panel → **Check for Updates…**
- Settings → About → **Check for Updates…**
- Automatic background checks are enabled via `SUEnableAutomaticChecks` in `Info.plist` (Sparkle’s default schedule applies).

Bare `swift build` binaries without the packaged `Info.plist` do not start Sparkle; the menu item opens the GitHub Releases page instead.

## Packaging note

`scripts/build-app.sh` embeds `Sparkle.framework` under `MacWispr.app/Contents/Frameworks/` and sets `@executable_path/../Frameworks` on the binary. Deep codesign (ad-hoc or Developer ID) must cover nested frameworks — existing `sign-and-notarize.sh` uses `--deep`.

## Security checklist

- [ ] `SUPublicEDKey` is the real public key (not the `PLACEHOLDER_…` string)
- [ ] Private key never appears in git history
- [ ] Appcast and zip URLs use HTTPS
- [ ] Tampered zip fails EdDSA verification (Sparkle will refuse the update)
- [ ] Users on ad-hoc builds may still need to re-grant Accessibility after update until Developer ID ships

## References

- https://sparkle-project.org/
- https://sparkle-project.org/documentation/
- https://github.com/sparkle-project/Sparkle
- Sample feed in-repo: [`website/appcast.xml`](../website/appcast.xml)
