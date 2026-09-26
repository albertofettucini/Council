# Council 1.3 — pre-release checklist (macOS 27)

This replaces `COUNCIL_TEST_CHECKLIST.md` for release gating. Tick every row before the app tag goes up.
Rows marked *second Mac* can't be verified on the build machine (macOS 27) — borrow one or note it as untested in the release notes.

| # | Check | Steps → expected | Done |
|---|---|---|---|
| 1 | Fresh zip, real quarantine | Download the release zip **in Safari**, unzip, drag `Council.app` to Applications, open it → macOS says it "could not verify" → **Done** → System Settings → Privacy & Security → scroll to Security → **Open Anyway** (within the hour) → password → app opens, onboarding card shows | [ ] |
| 2 | Homebrew, quarantined | `brew install --cask albertofettucini/council/council` → caveats text prints → first launch needs the same Open Anyway path as row 1 → opens | [ ] |
| 2 | Homebrew, `--no-quarantine` | `brew install --cask --no-quarantine albertofettucini/council/council` → opens straight away, no Gatekeeper prompt | [ ] |
| 3 | Sparkle hop from 1.2.0 | On an installed 1.2.0: Check for Updates sees 1.3.0 → installs → relaunches → **no Gatekeeper prompt** → the one-time **RE-ENTER THESE KEYS** sheet appears (every ad-hoc build has a new signature, so the keychain generation advances by exactly one) → keys re-entered inline work → no sheet on the next relaunch | [ ] |
| 4 | Apple seat on macOS 27 | Apple Intelligence seat answers a plain text question on macOS 27 (model rebuilt in 27; image input is NOT in 1.3 — the attached image is dropped for this seat exactly as in 1.2) | [ ] |
| 5 | Reminder: permission | Set **1W** on a journal card → the notification permission dialog appears **once** (not again on the next card) | [ ] |
| 5 | Reminder: banner → card | Change the Mac clock, or set a custom reminder 2 minutes out → banner arrives → clicking it opens the Journal **on that card** | [ ] |
| 5 | Reminder: notifications denied | Deny Council in System Settings → Notifications → the card shows the hint line → the in-app **OUTCOME DUE** section still works | [ ] |
| 6 | macOS 14 — *second Mac* | App launches; material fallback renders (no Liquid Glass, nothing blank); Apple seat shows the "needs macOS 26" message | [ ] |
| 6 | macOS 15 — *second Mac* | App launches; material fallback renders; Apple seat shows the "needs macOS 26" message | [ ] |
| 6 | macOS 26 — *second Mac* | App launches; Liquid Glass renders; Apple seat works text-only | [ ] |
| 7 | `council` CLI | `council "ping" --seats claude` → run lands in the same sessions folder the app shows in History; keys read from the same Keychain items (`council keys list`) | [ ] |
| 8 | Secret scan — all three repos | In the app, engine (CouncilKit) and tap repos run `grep -rIE -f ~/.config/council-release/secret-patterns.txt --exclude-dir=.git .` → **nothing printed**. The patterns file lives outside every repo on purpose (its contents would be the leak): the two Apple Team IDs, the real surname, the private email, the real first names, the home-folder path, and `BEGIN (OPENSSH\|RSA\|EC\|PRIVATE)` | [ ] |
| 9 | Versions in order | CouncilKit tag pushed **before** the app tag; pbxproj `minimumVersion` for CouncilKit bumped; `Package.resolved` committed; `CouncilKit.version` equals the APP version being tagged (X.Y.Z of vX.Y.Z — the engine tag is its own 0.x line, next 0.3.0) and the pbxproj reference is the REMOTE package pinned to that engine tag; local `main` fast-forwarded to `origin/main` (CI commits the appcast back) | [ ] |
