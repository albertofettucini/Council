# Council — Distribution (how a release is built and published)

Council ships **ad-hoc signed** — there is no paid Apple certificate, on purpose. macOS therefore
blocks the first launch ("could not verify"): users click Done, then System Settings → Privacy &
Security → scroll to Security → "Open Anyway" (the button only shows for about an hour after the
blocked launch), and confirm with their password. Right-click → Open still works on macOS 14 but
not on 15 or later. Every update after that goes through Sparkle.

Hardened Runtime is on, the App Sandbox is on with the entitlements the app actually needs
(network client, user-selected files read-write, app-scope bookmarks for the optional Engram
folder grant, library validation off, and Sparkle's two mach-lookup exceptions), and the
deployment target is macOS 14.0.

The notarized path is documented further down and stays available for the day a Developer ID
identity is in play — it is **not** what ships today.

---

## Automated releases (GitHub Actions) — the default path

`.github/workflows/release.yml` builds and publishes on a SemVer tag:

```sh
git tag v1.1.3
git push origin v1.1.3
```

**Before every release:**

1. `git fetch origin && git merge --ff-only origin/main` — CI commits the appcast back to `main`, so local
   `main` is usually one commit behind. Never force-push over it.
2. Tag and push the engine (CouncilKit) first, then the app.
3. If the app was built against the LOCAL engine during development (`XCLocalSwiftPackageReference`
   with `relativePath = "../CouncilKit-dev"` in `project.pbxproj`), switch that entry back to the
   `XCRemoteSwiftPackageReference` (repositoryURL `https://github.com/albertofettucini/CouncilKit.git`,
   `upToNextMinorVersion`, `minimumVersion` = the engine tag you just pushed) — CI cannot see a local path.
4. Re-resolve `Package.resolved` against that engine tag (it must now contain a `councilkit` pin) and commit it.
5. Run the secret scan (see `COUNCIL_QA_MACOS27.md`) over all three repos — it must return nothing.
6. After CI finishes, bump the Homebrew cask by hand (Step 5 below).

**Two repos, in this order.** The engine is its own package, so an app release that includes engine
changes is not one command:

1. In [CouncilKit](https://github.com/albertofettucini/CouncilKit): commit, tag the next engine version on its own 0.x line (e.g. `git tag 0.3.0`), push both.
2. In this repo: point the CouncilKit package reference at that version, re-resolve so
   `Package.resolved` pins it, commit, then tag and push `vX.Y.Z` — the workflow takes it from there.
3. After the Release is up, bump the Homebrew cask (Step 5 below) — CI does not touch it.

On that tag the workflow (on the `xcode-27` runner — macOS 27 + Xcode 27; `macos-26` is selectable as a fallback
when you run it by hand): builds `Council.app` (Release, **ad-hoc** signed —
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

The app ships **unsigned** (ad-hoc): users get a one-time Gatekeeper "could not verify" block and open
it via System Settings → Privacy & Security → "Open Anyway" (or skip it: `brew install --cask --no-quarantine`,
or `xattr -dr com.apple.quarantine /Applications/Council.app`). The **notarized** path below stays available
for whenever a paid Developer ID identity is in play — run `notarize.sh` locally and upload its stapled zip instead.

---

## Current state (what's done vs. what needs your account)

| Item | State |
|---|---|
| Hardened Runtime | ✅ on (`ENABLE_HARDENED_RUNTIME = YES`) |
| App Sandbox + entitlements | ✅ sandbox · `network.client` · `files.user-selected.read-write` · `files.bookmarks.app-scope` (Engram grant) · library validation off · Sparkle mach-lookups |
| Deployment target | ✅ macOS 14.0 |
| `exportOptions.plist` + `notarize.sh` | ✅ in `scripts/` (unused by the shipping path) |
| **Developer ID Application certificate** | ❌ none — by design, the project stays pseudonymous |
| **notarytool credentials** | ❌ none — see above |
| Team ID | ✅ none, on purpose — `CODE_SIGN_IDENTITY = "-"`, so the shipped build embeds no team |

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

---

## Step 5 — Bump the Homebrew cask (manual, every release)

The README's first install line is `brew install --cask albertofettucini/council/council`, and the
tap is live — but CI does **not** touch it. `Casks/council.rb` in
[albertofettucini/homebrew-council](https://github.com/albertofettucini/homebrew-council) pins
`version` and `sha256` by hand, so until you bump it every `brew install` still fetches the previous
release.

```sh
# after the GitHub Release is published
shasum -a 256 Council-1.2.0-macOS.zip     # or copy the SHA the workflow printed
# edit Casks/council.rb: version "1.2.0", sha256 "…"
brew style --fix Casks/council.rb
git commit -am "council 1.2.0" && git push
brew fetch --cask albertofettucini/council/council   # verify the checksum matches
```
