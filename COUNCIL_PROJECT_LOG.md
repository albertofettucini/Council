# Council — Project Log

A native **macOS SwiftUI** app where multiple LLMs (Claude, GPT, Gemini + 6 more)
answer the same question **in parallel**, optionally critique each other, and the
**human** decides. Not a chatbot — a roundtable. Solo-built, BYO-keys, local-only.

- **Platform:** macOS (deployment target macOS 14, with `#available(macOS 26.0)`
  gates for real Liquid Glass; falls back to `.material` on older systems).
- **Stack:** SwiftUI · Observation (`@Observable`) · Swift Concurrency
  (`async`/`await`, `withTaskGroup`) · Keychain · `URLSession.bytes` SSE streaming.
- **Repo state:** the app is 6 Swift files (~5,700 lines); the engine lives in the CouncilKit
  package (13 files, ~3,800 lines) and is shared with the `council` CLI. Build clean, 0 warnings.

---

## 1. The idea / philosophy

Single-model chat gives you one lens and hides disagreement. Council makes the
disagreement the product:

1. **Parallel, not sequential** — every advisor answers the same prompt at once.
2. **Blind peer review** — advisors critique each other's answers *anonymized*
   (no brand bias), then the UI de-anonymizes for the reader ("I disagree with
   Gemini", not "Advisor B").
3. **Divergence + Synthesis** — one chosen model maps where the advisors split,
   and (separately) writes a synthesis. The split is the signal.
4. **The human decides** — Council never picks a winner for you.
5. **BYO keys, local-only** — your keys live in the macOS Keychain; conversations
   are JSON files on your Mac. No server, no cloud, no telemetry.

---

## 2. Architecture

```
Council/
  CouncilApp.swift            App entry; hidden title bar; transparent window for behind-window glass
  Models/
    Archetype.swift           Seat persona archetypes (sage, etc.)
    LLMProvider.swift         9 providers + endpoints, key requirement, vision capability, model lists, prices
    Seat.swift                A council seat: optional provider, model, per-seat prompt, temperature, maxTokens
    Session.swift             Round (answers/peerReviews/divergence/synthesis/usage/answerProviders) + Session
    CouncilConfig.swift       Shareable council (no keys) + 4 curated presets
  Services/
    LLMClient.swift           Client protocol, message types, key-validation error mapping
    AnthropicClient.swift     Claude Messages API streaming (x-api-key)
    OpenAICompatibleClient.swift  OpenAI-format /chat/completions streaming (Bearer) — shared by 7 providers
    KeychainStore.swift       kSecClassGenericPassword get/set/delete — the ONLY key store
    Exporter.swift            Markdown / PDF / PNG share card / council.json
  Persistence/
    CouncilStore.swift        @MainActor @Observable brain: seats, rounds, history, ask/peerReview/
                              divergence/synthesis/regenerate, streaming, sessions, anonymization, config
  Views/
    ContentView.swift         The entire UI: sidebar, 3 advisor panels, round navigator, composer,
                              glass modifiers, Layout Tuner, Settings, provider/model pickers, share card
    MarkdownView.swift        Lightweight markdown renderer (headings, code blocks, think-blocks, inline)
```

**Data model:** session → ordered `[Round]`. Each `Round` carries its own answers,
peer reviews, divergence, synthesis, token usage, and `answerProviders` (seat id →
provider name, so a reopened session still labels panels even if a seat is later
re-assigned). All Codable types have lenient custom `init(from:)` (`decodeIfPresent`)
so a schema change never wipes saved data.

---

## 3. Feature inventory (what's built)

### Providers & seats
- **9 selectable providers:** Claude · GPT (OpenAI) · Gemini · DeepSeek ·
  Grok (xAI) · Mistral · Perplexity · OpenRouter · Ollama (local, no key).
  Apple on-device (Foundation Models) is modeled but not yet wired.
- **PICK YOUR MODEL flow** per panel: provider → model → API key (in that order),
  hover-to-open provider picker, duplicate-provider warning.
- **Optional/unassigned seats** — seats start empty; a nil-provider seat can never
  enter a round (guarded everywhere, no force-unwraps).
- **Per-model sampling** — temperature (0–2) and max tokens (≤64k), or AUTO.
- **Per-seat system prompt** override on top of a shared prompt.

### The roundtable
- **Round 1:** all keyed seats answer in parallel (streamed).
- **Peer Review:** each advisor reviews the others' answers, blind/anonymized,
  de-anonymized for the reader.
- **Devil's Advocate** seat role — gets an adversarial review brief instead of the
  standard one.
- **Divergence + Synthesis** — written by one chosen "synthesizer" seat; each round
  keeps its own, so follow-ups never wipe earlier analysis. Failed attempts surface
  as transient errors and are **never persisted** as content.
- **Regenerate** a single advisor's answer (clears that round's now-stale peer
  reviews + divergence + synthesis).
- **Stop / cancel** mid-stream — tears down the network request; partial text kept.

### Sessions & history
- **Multi-session history** with **search** (cached, fast).
- **Cost / token tracking** per round and per session (estimate).
- Local JSON per session in the app container; atomic writes; no keys, no image bytes.

### Export & sharing
- Export a session as **Markdown / PDF**, copy to clipboard.
- **Share card PNG** of the divergence/synthesis (optional subtle watermark).
- **Shareable council configs** (`council.json`) — provider/model/prompt/sampling,
  **never keys** — plus 4 built-in presets: *Code Review Council*, *Startup Red Team*,
  *Devil's Advocate Panel*, *Socratic Tutor*.

### UI / UX
- **Real Apple Liquid Glass** (`glassEffect`) + **behind-window vibrancy**
  (`NSVisualEffectView`, `.underWindowBackground`, transparent window) so the desktop
  shows through the chrome. Material fallback below macOS 26.
- **Layout Tuner (⌘D)** — live sliders for every spacing knob (window insets, sidebar
  width/gap, panel gap, corner radius, row gap, round-bar Y, export Y). Lets the dev
  hand-tune and bake values. Current baked layout is dialed in.
- Streaming caret, hover states, click-empty-to-deselect, Enter-to-focus composer,
  grouped Settings with a left rail, keyboard shortcuts, accessibility labels.

### Security model
- API keys **only** in the macOS Keychain (`kSecClassGenericPassword`).
- Shown **masked** via a plain `NSTextField` + bullet masking (deliberately not
  `NSSecureTextField`, to avoid the macOS Passwords autofill popover); the raw key
  lives only in transient `@State` and is wiped after handing to the Keychain.
- Keys are **validated with a tiny test call before saving**.
- Keys are **never** written to UserDefaults / disk / session JSON / exports / logs
  (codebase has zero `print`/`NSLog`), and each key is sent **only** to its own
  provider's endpoint. All remote endpoints are HTTPS (Ollama is localhost http).
- Only non-sensitive config (seat setup, prompts, sampling, synthesizer/devil choice,
  appearance, watermark) goes to UserDefaults.

---

## 4. Development history (by commit)

| Commit | What landed |
|---|---|
| `09e28a1` | Initial commit |
| `017e696` | Working multi-LLM council infrastructure (parallel calls, rounds, streaming) |
| `20e6ff5` | 9 providers, model picker, Devil's Advocate, image export, design + layout fixes |
| `958d248` | Model-before-key flow + adversarial-QA fixes to the seat state machine |
| `ca86a28` | Glassmorphism reskin + grouped Settings + provider-name persistence |
| `c77a122` | Real Liquid Glass (`glassEffect`) + backdrop experiments |
| `5e1b57d` | Behind-window glass + live Layout Tuner (⌘D) + dialed-in spacing |
| `54f73c2` | Finalized tuned layout + independent EXPORT nudge |
| `dfdd7c9` | **QA pass** — perf throttle, peer-review/spinner fixes, vision gating, hardening |

Earlier feature work (tracked, all shipped): multi-line composer, markdown + code
blocks, synthesis/divergence identity, stop/regenerate, cost tracking, md/PDF/copy
export, streaming, multi-session history, per-model parameters, keyboard shortcuts,
retry on failure, session-swap race fix, de-anonymized peer review, model
transparency + change-later, caret/chrome/a11y polish, shareable councils + presets.

---

## 5. The QA pass (latest) — what was tested and fixed

A full read-only audit ran three independent expert passes (correctness · performance ·
security). Findings and resolutions:

### Performance
- **[P0] Streaming render storm → FIXED.** Every SSE token was pushing a UI update,
  re-rendering a wide view tree and **re-parsing the whole markdown from scratch**
  (O(n²)), ×3 parallel seats, with an animated scroll each token. Fix: coalesce
  `onDelta` to **~30fps** in `streamCall` (always flush the final text). One localized
  change that collapses the four-way quadratic storm.
- **[P1] Search haystack rebuilt per keystroke → FIXED.** History search lower-cased
  every full transcript on every keystroke, and computed the result set twice per
  render. Fix: **cache** the per-session haystack (invalidated on save), compute the
  filtered list once per render.

### Correctness
- **[P1] Loading spinner showed on the wrong round → FIXED.** The per-seat status map
  is global; the spinner was gated by "is this the latest round," so peer-reviewing an
  older round showed no progress. Fix: a `generatingRound` tracker — the spinner now
  shows on the round actually working.
- **[P1] `peerReview` didn't set `deliberationBusy` → FIXED.** Now symmetric with
  divergence/synthesis (cleaner Stop + busy-lock behavior).
- **[P2] Images sent to text-only models → FIXED.** Attaching an image to a non-vision
  model (DeepSeek/Perplexity/Mistral/text Ollama) hard-failed with HTTP 400. Fix: a
  `supportsVision(model:)` capability check — images go only to vision-capable seats.
- **[P2] `applyConfig` partial-overwrite + unclamped import → FIXED.** A config with
  fewer than 3 seats left stale seats; imported temperature/maxTokens bypassed the
  clamps. Fix: clear trailing seats and clamp imported sampling (temp 0–2, tokens ≤64k).

### Security — verdict: CLEAN
- Independent audit **confirmed the core invariant holds**: API keys live only in the
  Keychain, are shown masked, are never persisted/logged/exported, and are sent only to
  their own provider endpoint. **No P0/P1 credential-leak issues.** Three P2 hardening
  notes remain optional (secure-event-input while typing a key; commit an explicit
  `.entitlements`; the import clamp — now done).

### Verified solid (checked, found correct)
Optional-provider guards everywhere · cancelled partials never corrupt history ·
failed divergence/synthesis never persisted · Codable backwards-compat · atomic session
writes · streaming cancellation wiring · bounds-checked round access under session swap.

---

## 6. Pre-launch hardening + Home dashboard (Session 2)

A second pass turned Council from "feature-complete" into "ready to hand to strangers":
launch viability, a real landing screen, and heavy visual polish.

### Launch hardening
- **Deployment target 26.5 → 14.0.** The app was accidentally pinned to the very latest
  macOS (≈nobody could run it). Lowered to 14.0; confirmed every Liquid-Glass call is
  `#available(macOS 26.0)`-gated so the material fallback actually ships on 14–25.
- **App Sandbox kept on, made functional.** It uses Xcode's build-setting synthesis
  (`ENABLE_APP_SANDBOX`, `ENABLE_OUTGOING_NETWORK_CONNECTIONS=YES`). Flipped
  `ENABLE_USER_SELECTED_FILES` `readonly → readwrite` so exports work in the sandbox.
  Verified the signed build's entitlements: app-sandbox + network.client +
  files.user-selected.read-write. (Network was never actually blocked — earlier worry
  was wrong; the real gap was file write.)
- **Code signing / notarization scaffolding.** `scripts/notarize.sh` (archive → export
  Developer ID → zip → `notarytool submit --wait` → `staple` → verify),
  `scripts/exportOptions.plist`, and `DISTRIBUTION.md` with exact one-time steps. The dev
  must still create a **Developer ID Application** cert + store notary creds (only
  "Apple Development" exists on the machine; team YOUR_TEAM_ID vs personal YOUR_TEAM_ID — pick
  one). Hardened Runtime already on.
- **Layout Tuner hidden in release** — the ⌘D dev tuner is `#if DEBUG` only; absent from
  shipping builds.

### Default divergence (so the council isn't redundant on first use)
- Three **general-purpose lens personas** ship as default seat prompts: **Analyst**
  (first-principles), **Practitioner** (what works in practice), **Skeptic** (challenges
  the easy answer). Each still answers fully — they just enter from different angles, so a
  first-time question genuinely diverges. Seat key bumped `v6 → v7`.

### Home dashboard (the app now opens here, not the roundtable)
- Sidebar gets a **HOME** item (default). Entering the roundtable: New Directive, a
  Quick-Start preset, a recent session, or a hero example.
- **Living hero** — ambient orbiting/"breathing" advisor orbs (`TimelineView`), a rotating
  example directive (50 neutral, non-leading questions; click → opens the roundtable
  pre-filled), and a rotating ethos line.
- **USAGE + SPEND** card — lifetime tiles (total / this month / sessions) + a smooth
  gradient **area sparkline** of recent costs + this-week / avg-per-session / top-model.
- **YOUR COUNCIL** — each seat: persona + descriptor + provider · model + key dot, Configure.
- **QUICK START** — the 4 presets, one click loads + enters the roundtable.
- **PROVIDERS** — 9 providers in a 2-col grid with price/1M + key status, click → Settings.
- **RECENT** — last sessions with a one-line answer preview + date + cost.
- Single-glance, no scroll: a `Grid` pairs cards at equal height per row so there's no
  blank band under the shorter card (the fix: stretch the glass **inside** `dashCard`
  before the `.glassPanel`, not after).

### Background tint palette
- A right-edge **color rail** (no icon, just swatches): None + 12 solids + 10 two-color
  gradient mixes. Two-color swatches render as a **diagonal split disc**; None shows a slash.
- Big circular hit-areas; hover grows the swatch; selection wears a ring; the list
  bottom-fades (mask) to hint "scroll for more".
- The tint washes the behind-window glass with a **`.color` blend** so the chosen hue reads
  true (blue stays blue instead of going purple over a warm desktop). Persisted; the
  Settings sheet mirrors the same tint so it harmonizes with the app.

### Other polish & one feature
- **First-run onboarding** — a two-beat dismissible glass card: the COUNCIL wordmark fades
  up, tap reveals the explainer (BYO-key, 100% local, "one key is enough"), then CONTINUE.
- **Spend alert** (Settings → App) — opt-in local notification once total spend crosses a
  $ threshold (requests authorization on enable; fires once per threshold).
- **Light-mode hover/selection fixed** — `glassBright` is now dark-in-light (white-on-white
  was invisible), so every button's hover/active state reads in both modes; sidebar handle
  got a hover state too.
- **Settings cards de-browned** — dropped `ultraThinMaterial` (it sampled the warm desktop
  and turned cards brown) for flat neutral fills; tightened section spacing.

**State:** ~5,100 LOC, build clean, 0 warnings. Opens to a polished Home; roundtable
intact. Not yet run end-to-end against live keys; not yet notarized (needs the dev's
Developer ID — see `DISTRIBUTION.md`).

### Still on the roadmap

Shipped since this was written: the on-device Apple seat, the decision journal (plus outcome
reminders), selective deliberation, the guest seat, the neutral chair, and parse-markdown-once.

Still open: more local backends out of the box; recalling past decisions when a new question
resembles an old one; lazy/indexed session loading.

## 7. Scroll-performance pass (Session 3)

The color rail stuttered while scrolling. A long hunt by elimination found the real cause
and a couple of genuine wins along the way:

- **[ROOT] Continuous orb animation** — the hero's ambient orbs ran a `TimelineView(.animation)`
  forever, so the app **never went idle** → every scroll frame competed with a constant
  redraw across the glassy Home. Fix: the orbs now animate **only while the hero is hovered**
  (`AdvisorOrbs(animate:)`), static otherwise. This was the actual jank.
- **[REAL] Keychain reads in the render path** — `YOUR COUNCIL` (3) + `PROVIDERS` (9) called
  `hasKey`/`keyExists`, each doing a **synchronous Keychain read**, ~12 per render. Cached
  into a `Set<LLMProvider>` (`keyCache`), rebuilt only when a key changes — never from a body.
- **Misfires found & reverted:** `.mask` on the scroll, `.color`-blend background, and the
  `drawingGroup()`s I added to "help" were either neutral or actively harmful (drawingGroup on
  an animating view re-rasterizes every frame). All removed.
- **Opaque window** — dropped the behind-window "desktop-through" curtain (`isOpaque = true`,
  within-window vibrancy). The frosted backdrop + Liquid Glass cards stay; the desktop no
  longer shows through (user preference) and the window server stops recompositing against it.
- **Performance toggle** — Settings → App → "Reduce glass for performance" (`council.liteMode`,
  default off) swaps real Liquid Glass for the cheap material path for users on weaker Macs.

Net: the full Liquid-Glass look is back AND scrolling is smooth. Lesson: a single
always-on animation can tax an entire glassy UI far more than the glass itself.

## 8. Polish pass (Session 4)

- **Dashboard data audited & verified** (adversarial review): all cost/stat aggregates
  compute correctly; no key is ever read or shown by the dashboard/notification code.
  Fixed two spend-alert bugs (only burn the one-shot once authorization is confirmed;
  re-arm on re-enable / threshold change). SPEND "this week" now shows spend, not a
  session count. Removed dead code + two Sendable warnings.
- **Onboarding animation made cinematic & consistent** — all three beats now reveal with
  the same slow blur-focus (COUNCIL wordmark in, tap→card, CONTINUE→app), ~1.1–1.2s.
  **Root fix:** the dismiss was driven by an `@AppStorage` flag, whose change propagates
  asynchronously and so was *not captured by `withAnimation`* → the exit kept playing
  instantly no matter the duration. Now a local `@State` drives the transition (the
  `@AppStorage` is persistence only), so it animates reliably.
- A Desktop `Council.app` symlink points at the Release build for one-click launching.

## 9. Peer Review page + sidebar polish (Session 5)

- **Peer Review is now its own full page** (like Divergence/Synthesis) — each advisor's
  critique as an attributed, de-anonymized card; Devil's Advocate badged. The inline
  per-panel peer review was removed, so all four deliberation stages
  (ROUNDTABLE / PEER REVIEW / DIVERGENCE / SYNTHESIS) are consistent screens.
- **Ambient orbs animate only while hovering the orbs** themselves (not the whole hero).
- **History rows** got the hover highlight, matched exactly to the sidebar mode rows.
- **Background tint dialed back** 0.5 → 0.28 (it was flooding the UI with the chosen hue).
- **Sidebar clears the window chrome**: dedicated insets so the card clears the macOS
  traffic lights at top and lifts off the bottom — without moving the dashboard.
- **Layout finalized & locked**: the dialed-in spacing is baked in and the ⌘D Layout
  Tuner (overlay, shortcut, knob list, the whole struct) was removed so it can't drift.

## 10. Pre-launch hardening + app icon (Session 6)

- **App icon** — the app finally has a real icon: a council of three orbs on a carbon-fiber
  squircle (metallic spheres), designed in Stitch and imported to a full macOS `.appiconset`
  (16→1024) + `docs/icon.png` via `scripts/import_stitch_icon.py` (flood-fills the white
  export canvas to transparent, follows the squircle edge, re-frames with native margin +
  shadow). `CFBundleIconName` wired; INFOPLIST copyright filled.
- **Ollama connectivity fixed** — the sandboxed Release app couldn't reach a local Ollama
  because ATS blocks plaintext `http://localhost`. Added `NSAllowsLocalNetworking` via a
  repo-root `Council-Info.plist` (merged through `INFOPLIST_FILE` while keeping
  `GENERATE_INFOPLIST_FILE`): loopback / `.local` HTTP allowed, every real domain still
  HTTPS. Connection failures are now provider-aware ("Can't reach Ollama … is it running?").
- **First-run UX** (surfaced by a pre-launch review) — the PROVIDERS board and YOUR COUNCIL
  "Configure" now open the seat panels (where keys are actually entered) instead of Settings;
  each key step links to that provider's API-key console; the Home hero question auto-runs
  once at least one seat is keyed; dead `homeQuery` state removed.
- **Explainers** — an ⓘ popover + an empty-state description on Peer Review / Divergence /
  Synthesis so a newcomer learns what each does before generating.
- **Open-source artifacts** — `README.md`, `LICENSE` (MIT), and the authorship comment set
  to the public "Joseph" persona. A security/privacy pass confirmed API keys live only in
  the Keychain and nothing sensitive ships.
- Release build clean (0 warnings).

---

*Generated as a running project record. Update as features land.*
