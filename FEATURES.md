# Council — Feature Spec (MVP → v1)

> **Historical spec.** This is the original MVP build plan. Several items it lists under DEFER / Tier-3
> (e.g. local models via Ollama / OpenAI-compatible endpoints, per-model parameters) have since shipped —
> this file is kept as the design snapshot, not a current status report. See the README for what's live.

> Paste this to Claude Code, or keep it in the repo as `FEATURES.md`. It defines WHAT to build and, just as importantly, HOW to keep it minimal.

## PRIME DIRECTIVE: MINIMAL UI

Council's identity is a **clean, calm, minimal interface** — the deliberate opposite of the cluttered dashboards every competitor ships (BoltAI, Msty, TypingMind drown the user in panels, badges, and buttons). Every feature below is essential, but **how** it appears on screen is not negotiable: implement each one in the most minimal, hidden-until-needed way possible.

When a feature would add visible clutter, find the quieter way. **If forced to choose between feature visibility and visual calm, choose calm** — the feature can live one keystroke or one click away.

## Minimal-UI rules (apply these to EVERY feature)

1. **Progressive disclosure.** Show only what the current moment needs. Advanced controls stay hidden until explicitly opened.
2. **One primary action per view.** The main canvas has a single obvious thing to do; everything else is secondary.
3. **Keyboard-first.** Prefer a command palette (⌘K) and shortcuts over rows of visible buttons.
4. **Tuck secondary functions away.** Settings, parameters, key management, export — these live in sheets/menus, never on the main canvas.
5. **Let typography and whitespace do the work.** Avoid borders, badges, and chrome that don't earn their place.
6. **No decoration masquerading as information.** No fake telemetry, no status noise.

---

## TIER 1 — TABLE STAKES (cannot launch without these)

### 1. Multi-provider model support + easy add/switch
**What it is:** Connect Claude, GPT, and Gemini (at minimum) and let the user choose which models sit as advisors at the table.
**Why essential:** This is the reason the whole category exists. Without it, Council isn't a council.
**Minimal UI:** No model-management dashboard on the main screen. Model selection lives in a single quiet settings sheet. On the main canvas, an advisor is just its name + status — nothing more. Build the provider layer against an OpenAI-compatible abstraction so adding providers later costs almost nothing in code and zero in UI.

### 2. BYOK keys in macOS Keychain, direct to provider
**What it is:** The user pastes their own API keys; keys are stored encrypted in the system Keychain, and requests go straight to each provider — never through any server of yours.
**Why essential:** Trust. Users distrust apps that could harvest keys; Keychain storage is expected, not a bonus. It is also Council's strongest open-source trust story (the code is auditable).
**Minimal UI:** Key entry is a masked field (SwiftUI `SecureField`), shown only when an advisor is offline/unconfigured. Once a key is set, the field disappears — no permanent settings clutter. State plainly, somewhere quiet: "Keys stay on your Mac; requests go directly to each provider."

### 3. Persisted, searchable conversation history
**What it is:** Every council session is saved and reloadable; the user can search past sessions and rename them.
**Why essential:** The #1 feature users abandon tools for lacking. A deliberation you can't revisit has no lasting value.
**Minimal UI:** History is a collapsible side list (you already have a collapsible sidebar) or behind a single icon — not a permanent heavy panel. Search is one field at the top of that list, not a separate screen. **Persist the entire deliberation object** (every advisor's Round 1, Peer Review, Divergence, Synthesis), not a flattened transcript, so reopening a session restores the full pipeline. Use local SQLite.

### 4. Streaming responses, per advisor panel
**What it is:** Each advisor's answer appears token-by-token as it's generated, independently in its own panel.
**Why essential:** So expected that users only notice its absence; with multiple panels, non-streaming feels frozen.
**Minimal UI:** No extra UI needed — this is behavior, not chrome. Stream each advisor independently so a fast model fills in while a slow one is still thinking. A subtle per-panel "thinking" indicator is enough; no progress bars or spinners everywhere.

### 5. Markdown + code blocks (syntax highlight + copy)
**What it is:** Render responses as proper markdown; code blocks get syntax highlighting and a copy button.
**Why essential:** When present it's a favorite feature; when broken (raw tags, un-copyable code) it's a top reason people quit.
**Minimal UI:** Clean typographic markdown — no boxed-in heaviness. The copy button appears on hover over a code block, not as a permanent button. Render any reasoning / `<think>` content as a collapsible block so it doesn't dominate the panel.

### 6. Parallel fan-out + side-by-side comparison
**What it is:** One question goes to all advisors at once; their answers sit side by side. This is your "Round 1."
**Why essential:** Table stakes for the multi-LLM category — the deciding factor users cite for choosing these tools over single-model chat.
**Minimal UI:** You already have this: one input → three panels. Keep the panel layout legible at three advisors; resist adding per-panel toolbars. The input bar stays the single focal point.

---

## TIER 2 — STRONGLY EXPECTED (credible tools have these)

### 7. Synthesis with preserved divergence  ←  YOUR IDENTITY FEATURE
**What it is:** After the advisors answer (and review each other), Council produces a final synthesis that includes (a) the answer, (b) where advisors agreed, and (c) the dissent/divergence — who disagreed and why.
**Why essential:** Your pipeline's whole promise is a trustworthy final answer. Competitors pair synthesis with *visible* disagreement; a blended answer that hides the dissent is exactly what users complain about. This is what makes Council *Council*.
**Minimal UI:** The Synthesis view is calm and readable — a clear final answer, with "agreement" and "divergence" as quiet, well-typed sections (not loud color-coded badges). This is your most screenshot-worthy, exportable artifact, so it should feel like a clean verdict, not a data dump.

### 8. Export (markdown / PDF / copy)
**What it is:** Export a full council session — including divergence and synthesis — to markdown or PDF, or copy it.
**Why essential:** A deliberation that can't leave the app has little decision value; export is the natural deliverable of a synthesis.
**Minimal UI:** A single export action in a menu or the command palette. Markdown first (cheap, GitHub-friendly), PDF later. No export-options panel — sensible defaults.

### 9. System prompts / per-advisor personas
**What it is:** A global system prompt plus an optional role/instruction per advisor (e.g. skeptic, optimist, domain expert).
**Why essential:** Personas are what make three models give genuinely *different* perspectives instead of three near-identical answers. Assigning opposing dispositions is the core of useful deliberation.
**Minimal UI:** Persona/instruction lives in the advisor's quiet config sheet, with a few presets. The main canvas shows at most the persona name under the advisor — never the full prompt.

### 10. Stop/cancel + regenerate
**What it is:** Cancel a running generation (per advisor and all at once) and regenerate a single advisor's answer or re-run a round.
**Why essential:** With parallel multi-model fan-out, a runaway or expensive generation must be stoppable; regenerate is a baseline affordance.
**Minimal UI:** The send/EXECUTE button becomes a stop button while generating (same spot, no new control). Regenerate appears on hover over an advisor's answer.

### 11. Cost / token tracking + pre-run estimate  ←  URGENT FOR COUNCIL
**What it is:** Show running token/cost per session, and ideally an estimate before launching a multi-round deliberation.
**Why critical for you specifically:** Council fans out to 3+ models across *multiple rounds* — a four-stage pipeline across three models is roughly 12+ API calls per question. BYOK means the user pays the provider directly, so unpredictable spend is a real bill-shock risk and a top BYOK complaint. This is simultaneously expected AND a genuine differentiator (a transparent, cost-aware council).
**Minimal UI:** A small, quiet cost readout (e.g. a discreet number in the footer or near the input), not a charts dashboard. Before a full multi-round run, a one-line estimate ("~$0.04 · 12 calls") — calm, informative, dismissible.

### 12. Multi-line input + file/image attachments
**What it is:** A proper multi-line composer; attach images/documents that get routed to vision-capable advisors.
**Why essential:** Multi-line is mandatory; document/image Q&A is now a baseline expectation.
**Minimal UI:** Multi-line composer at launch. Attachment is a single icon in the input bar (you already added it); attached files show as a small thumbnail chip above the input, not a heavy attachment panel. Degrade gracefully for models that can't accept images.

---

## TIER 3 — POLISH (ship soon; won't sink launch day one)

- **Folders / tags for sessions** — only matters once history grows. Keep it inside the history list, not a new nav level.
- **Light/dark theme + keyboard shortcuts** — default to "follow system appearance." Shortcuts reinforce the keyboard-first, minimal ethos.
- **Per-model parameters (temperature, max tokens)** — tucked in the advisor config sheet, collapsed by default. Most users never open it.
- **Reliability: error handling, retry, rate-limit handling, graceful partial failure** — invisible but essential. One provider's error must not blank the others; show a quiet per-advisor error state, not a modal.
- **Global hotkey / menu-bar access** — native-macOS polish; a single quick-ask shortcut.

---

## DEFER (architect for it, don't build it yet)

Local models (Ollama / LM Studio), RAG / knowledge base, web-search grounding, plugins / MCP, voice, mobile, cloud sync. Build the provider layer OpenAI-compatible so local models slot in later with minimal UI cost. These are post-launch prestige adds, not MVP.

---

## BUILD ORDER

1. **Tier 1 (#1–6)** — the credibility gate. Do not launch publicly without all six.
2. **Tier 2 (#7–11)** — Council's identity. Prioritize **#7 (synthesis + divergence)** and **#11 (cost visibility)**: both expected by the deliberation category AND your sharpest differentiation.
3. **Tier 3** — polish and retention; pull reliability earlier if early users hit rate limits.
4. **Deferred** — local models + web-search grounding are the highest-leverage post-launch adds for an open-source audience.

**Throughout: when in doubt, choose the calmer, more minimal implementation.** Council's edge is that it does the essential things every competitor does — but quietly, and beautifully.
