# Council — Distribution (sign · notarize · staple for GitHub Releases)

Goal: a `.zip` users can download from GitHub and open with **no Gatekeeper warning**.
The project is already set up for this — Hardened Runtime is on, the App Sandbox is on
with the right entitlements (network client + user-selected files read-write), and the
deployment target is macOS 14.0 so it runs on the broad install base.

You run the steps below **once** to set up credentials, then `notarize.sh` each release.

---

## Automated releases (GitHub Actions) — the default path

`.github/workflows/release.yml` makes a release one command: **push a SemVer tag.**

```sh
git tag v1.1.3
git push origin v1.1.3
```

On that tag the workflow (on a `macos-26` runner): builds `Council.app` (Release, **ad-hoc** signed —
the project already uses `CODE_SIGN_IDENTITY = "-"`, so no paid Apple cert is needed), zips it, signs
the zip with the Sparkle **EdDSA** key, regenerates `appcast.xml` and **commits it back to `main`**
(Council serves the appcast from `raw.githubusercontent.com/.../main/appcast.xml`), then publishes the
GitHub Release with the zip + SHA256. `CFBundleVersion` is derived from the tag as
`major*10000 + minor*100 + patch` (monotonic, so Sparkle sees every release as newer).

**One-time setup — add the Sparkle private key as a repo secret (it never enters the repo):**

```sh
# Council reuses the SAME EdDSA key as Engram (it's already in your login Keychain — its public half
# is in Council-Info.plist's SUPublicEDKey). Export it and set it as the Council repo secret:
/path/to/Sparkle/bin/generate_keys -x sparkle_private_key
gh secret set SPARKLE_ED_PRIVATE_KEY -R albertofettucini/Council < sparkle_private_key
rm -f sparkle_private_key
```

The app ships **unsigned** (ad-hoc): users get a one-time Gatekeeper "unidentified developer" prompt and
open with right-click → Open. The **notarized** path below stays available for whenever a paid Developer
ID identity is in play — run `notarize.sh` locally and upload its stapled zip instead.

---

## Current state (what's done vs. what needs your account)

| Item | State |
|---|---|
| Hardened Runtime | ✅ on (`ENABLE_HARDENED_RUNTIME = YES`) |
| App Sandbox + entitlements | ✅ sandbox + `network.client` + `files.user-selected.read-write` |
| Deployment target | ✅ macOS 14.0 |
| `exportOptions.plist` + `notarize.sh` | ✅ in `scripts/` |
| **Developer ID Application certificate** | ❌ **not on this Mac** — only "Apple Development" exists |
| **notarytool credentials** | ❌ not stored yet |
| Team ID | ⚠️ project = `YOUR_TEAM_ID`, but the only cert here is personal team `YOUR_TEAM_ID` — pick one |

---

## Step 1 — Create a "Developer ID Application" certificate (one-time)

Easiest path (Xcode):
1. Xcode ▸ Settings ▸ **Accounts** ▸ select your Apple ID ▸ **Manage Certificates…**
2. Click **+** ▸ **Developer ID Application** ▸ Done.
3. Confirm it's installed:
   ```sh
   security find-identity -v -p codesigning | grep "Developer ID Application"
   ```
   You should see: `"Developer ID Application: Your Name (TEAMID)"`.

**Decide your team.** The project's `DEVELOPMENT_TEAM` is `YOUR_TEAM_ID`. The only cert on
this Mac is personal team `YOUR_TEAM_ID`. Create the Developer ID cert under whichever team
you want to ship under, and make sure that team's ID is used in Steps 2–3 (and matches
`DEVELOPMENT_TEAM` + `scripts/exportOptions.plist`). For a solo GitHub release, the
personal team is fine — if you go that way, change both to `YOUR_TEAM_ID`.

## Step 2 — Store notarization credentials (one-time)

Create an **app-specific password** at <https://appleid.apple.com> ▸ Sign-In & Security ▸
App-Specific Passwords. Then:

```sh
xcrun notarytool store-credentials CouncilNotary \
  --apple-id "YOUR_APPLE_ID_EMAIL" \
  --team-id  "YOUR_TEAM_ID" \
  --password "xxxx-xxxx-xxxx-xxxx"     # the app-specific password
```

(Alternatively use an App Store Connect API key with `--key`, `--key-id`, `--issuer`.)
This saves the credentials in your keychain under the profile name `CouncilNotary`, so no
secret ever lives in the script or the repo.

## Step 3 — Build, notarize, staple

```sh
TEAM_ID=YOUR_TEAM_ID ./scripts/notarize.sh
```

What it does: archive (Release) → export with Developer ID → verify signature/entitlements
→ zip → `notarytool submit --wait` → `stapler staple` → re-zip the stapled app → Gatekeeper
check. Output: **`build/Council-notarized.zip`**.

If notarization is rejected, see the log:
```sh
xcrun notarytool log <submission-id> --keychain-profile CouncilNotary
```

## Step 4 — Publish

Upload `build/Council-notarized.zip` to a **GitHub Release**. Because the app is stapled,
it opens cleanly even offline — no "unidentified developer" prompt.

---

## Optional — ship a .dmg instead of a .zip

A zip is perfectly fine for GitHub. If you prefer a drag-to-Applications `.dmg`:

```sh
brew install create-dmg
create-dmg --volname "Council" --app-drop-link 450 180 \
  "build/Council.dmg" "build/export/Council.app"
# then notarize + staple the .dmg the same way (notarytool submit build/Council.dmg ...,
# stapler staple build/Council.dmg)
```

## Re-signing for each new release
Bump `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` in the project, then re-run Step 3.
Steps 1–2 are one-time.
