# Signing, notarization, and Accessibility TCC

## Why the shortcut “dies after every update”

macOS **Transparency, Consent, and Control (TCC)** binds the Accessibility
grant to the app’s **code signature identity**.

| Signing | Team ID | Accessibility across updates |
|---------|---------|------------------------------|
| Ad-hoc (`codesign -s -`) | *none* | **Invalidated** when the binary hash changes |
| Developer ID Application | stable TEAMID | **Persists** across updates of the same bundle ID |

Ad-hoc builds re-key TCC on every release. Users must re-enable **System
Settings → Privacy & Security → Accessibility → MacWispr**. Most will not —
they report “the shortcut stopped working.”

**1.2.2+ shipping path:** Developer ID Application (Team `UTSTY3J6NS`) so the
Accessibility grant **persists** across updates of the same bundle ID.

### What still needs Accessibility even after Carbon hotkey work

| Capability | Needs AX? | Notes |
|------------|-----------|--------|
| Detect ⌥Space (Carbon hotkey) | Often **no** | Detection can survive a dropped grant |
| Swallow Space (CGEvent tap) | **Yes** | Otherwise Option+Space types NBSP |
| Paste / type into frontmost app | **Yes** | `TextInserter` synthetic ⌘V |
| Global NSEvent monitors | **Yes** | Install but never fire without AX |

So: Carbon fixes **detection**. Paste is still dead without AX. From the
user’s seat that is still “shortcut does nothing” (hotkey → listen → text on
clipboard only, nothing typed). 1.2.x surfaces that via failure banner / warning;
it does not remove the AX requirement for insertion.

## Durable fix (do this once)

### Easiest: CLI helper (recommended)

Apple still requires **one browser click** to issue the cert (they will not mint
Developer ID offline). Everything else is terminal:

```bash
./scripts/setup-signing.sh
# 1. Script generates CSR + opens Apple's cert page
# 2. Choose "Developer ID Application", upload the CSR it shows in Finder
# 3. Download the .cer — drop it in .signing/ or ~/Downloads/
# 4. Script imports it, stores notary credentials, writes .env.signing
source .env.signing && ./scripts/build-app.sh
```

Team ID for this project: `UTSTY3J6NS`.

If you already downloaded the `.cer`:

```bash
./scripts/setup-signing.sh --import ~/Downloads/developerID_application.cer
```

### Manual equivalent

1. **Apple Developer Program** membership (active).
2. Create a **Developer ID Application** certificate in
   [Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/certificates/list).
3. Install the cert + private key in the build machine keychain (export/import `.p12` if needed).
4. Create an [app-specific password](https://appleid.apple.com) for notarytool, then:

```bash
xcrun notarytool store-credentials "MacWispr-notary" \
  --apple-id "you@example.com" \
  --team-id "UTSTY3J6NS" \
  --password "app-specific-password"
```

5. Ship releases with:

```bash
source .env.signing   # or export MACWISPR_SIGN_IDENTITY / MACWISPR_NOTARY_PROFILE
export MACWISPR_VERSION=1.2.2   # bump for each release
./scripts/build-app.sh          # signs via sign-and-notarize.sh
./scripts/build-dmg.sh
# Sparkle-sign the zip, update website/appcast.xml length + edSignature, then:
./scripts/release.sh v1.2.2
wrangler pages deploy website --project-name=fuckwisprflow
```

Or skip notarization while testing (common when Keychain profile is missing):

```bash
export MACWISPR_SIGN_IDENTITY="Developer ID Application: Your Name (UTSTY3J6NS)"
export MACWISPR_SKIP_NOTARIZE=1
./scripts/sign-and-notarize.sh dist/MacWispr.app
# or build-app.sh with the same env
```

If notarytool says `No Keychain password item found for profile: MacWispr-notary`,
re-run `store-credentials` (above) or keep `MACWISPR_SKIP_NOTARIZE=1` for local builds.

## Verify a build

```bash
codesign -dv --verbose=4 /Applications/MacWispr.app 2>&1 | grep -E 'Authority|TeamIdentifier|flags'
# Expect:
#   Authority=Developer ID Application: ...
#   TeamIdentifier=XXXXXXXXXX
#   flags=0x10000(runtime)   # hardened runtime — not flags=0x2(adhoc)

spctl -a -vv /Applications/MacWispr.app
# Expect: accepted (notarized)
```

## Local / CI ad-hoc (default)

With no `MACWISPR_SIGN_IDENTITY`, `build-app.sh` still ad-hoc signs so local
dev works. That is fine for `./scripts/install.sh` on your machine — not fine
for public downloads if you want Accessibility to stick.

## Hardened runtime entitlements

See `MacWispr.entitlements`:

- `device.audio-input` — microphone  
- `cs.allow-jit` / `allow-unsigned-executable-memory` / `disable-library-validation` — MLX Metal runtime  

Tighten these once MLX load paths are fully understood under library validation.
