<p align="center">
  <img src="docs/icon.png" width="128" alt="Council icon">
</p>

<h1 align="center">Council</h1>

<p align="center">
  <b>Several AIs answer. Council shows you where they disagree.</b><br>
  A native macOS app that asks several different models the same question, has them review
  each other blind, scores how far apart they landed, and puts the lone dissenter in front of
  you instead of averaging it away.
</p>

<p align="center">
  <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-1a1a2e">
  <img alt="Swift 6" src="https://img.shields.io/badge/Swift-6-1a1a2e">
  <img alt="SwiftUI" src="https://img.shields.io/badge/SwiftUI-native-1a1a2e">
  <img alt="License: MIT" src="https://img.shields.io/badge/License-MIT-1a1a2e">
</p>

---

## The idea

Asking one model a hard question gives you one model's blind spots. Council convenes
a panel instead. The same prompt goes to several advisors at once — Claude, GPT,
Gemini and more — each answers independently, and then the interesting part begins.

## How it works

1. **Ask.** Pose a question to your council (three advisors; each seat can be any of twelve backends).
2. **Parallel answers.** Every advisor responds at once, streaming live in its own panel.
3. **Blind peer review.** Each advisor critiques the others' answers without knowing who wrote them — no brand bias, just the argument.
4. **Divergence — with a score.** A 0–100 read of how far apart the council landed, how many camps formed, and who the outlier is. It measures agreement, not correctness.
5. **Debate (optional).** One bounded rebuttal round: each advisor revises or holds, and says why. Who moved, who held.
6. **Synthesis & Dissent.** A decision-ready distillation — plus the outlier's full answer spotlighted, because the majority can be confidently wrong together.
7. **You decide — and log it.** Record your decision in the journal, and later, how it actually turned out.

### Bring an outside answer

Already asked ChatGPT, Claude or Gemini? Paste that answer in as a **guest seat** before you ask
(the 🎭 button by the question box). If only one advisor answered your latest question, the
second-view card under that round lets you paste one into it instead. It takes a place at the
table as one more anonymous advisor: the council reviews it blind, without knowing it came from
outside, and it counts in the divergence score, the dissent and the synthesis. Adding or replacing
a guest after the round clears that round's analysis, so you run it again with the guest included.
One connected advisor plus a guest is already a council of two.

## Features

- 🧠 **Twelve backends** — Claude · GPT (OpenAI) · Gemini · DeepSeek · Grok (xAI) · Mistral · Perplexity · OpenRouter · Ollama (local, needs [Ollama](https://ollama.com) running) · Apple Intelligence (on-device, free — needs macOS 26 on Apple-silicon) · two **custom OpenAI-compatible endpoints** (llama.cpp, LM Studio, vLLM, a second Ollama box — with a test-connection button that pulls the server's real model list)
- ⚡ **Live streaming** answers, side by side
- 🎭 **Distinct personas** per seat (Analyst · Practitioner · Skeptic) for real divergence — not three ways of saying the same thing
- 🎭 **Guest seat** — paste an answer from any other AI before you ask, or into a one-answer round; it's blind-reviewed as one more anonymous advisor
- ⚖️ **Neutral chair** (optional) — a model that moderates instead of answering: it writes the divergence and synthesis, and closes a debate with a neutral summary
- 😈 **Devil's Advocate** role to pressure-test the consensus
- 📊 **Divergence score** — 0–100 how far apart the council landed, camps, and the outlier; agreement, not correctness
- 🗣️ **Bounded debate** — one optional rebuttal round; original answers stay tucked underneath so you see what moved
- ☑️ **Selective deliberation** — after reading the answers, choose which of them go into peer review
- ❗ **Dissent** — the outlier's full answer, surfaced on its own to judge for yourself
- 🧪 **Example council** — a real recorded session ships with the app, clearly labelled and read-only, so you can see a full council before adding a single key
- 📓 **Decision journal** — log what you chose, set a reminder, and macOS notifies you when it's time to record how it turned out (local only, no account)
- 🧭 **Two layouts** — Flow (one page; analysis appears beneath the answers) or Classic (each stage its own screen)
- 🖼️ **Vision** — drop in an image for the models that support it
- 📎 **Attach a document** — add a `.md`/`.txt` to your question (or drag it in) and the whole council reads it before weighing in; documents up to 20,000 characters (sent without an image) are kept with the session so Regenerate can re-ask; larger ones, and images, are never saved
- 💸 **Calm cost estimate** — a running token/$ tally, your spend at a glance, and an optional spend alert
- 📤 **Export** — Markdown, PDF, image, or a paste-ready **decision memo**; **share councils** as importable presets
- ⌨️ **`council` CLI** — the same engine in your terminal: pipe documents in, get JSON out, gate CI on divergence
- 🔄 **In-app updates** — new versions install from inside the app (it's an unsigned build, so macOS won't hand the new version the old one's Keychain items — Council asks you to re-enter your keys once, inline)
- 🔗 **Engram bridge** (optional) — if you already run [Engram](https://github.com/albertofettucini/Engram), a journal decision can be written into your local Engram store, so your other AI tools can recall it
- 💾 **Local history** of every session (CLI runs land there too)
- 🪟 **Native SwiftUI** — real Liquid Glass on macOS 26, a graceful material fallback on 14+

## Privacy — bring your own keys

**No account, no server, no telemetry.** Questions go only to the providers you pick.

- Your API keys live **only in the macOS Keychain.** They're masked in the UI and are **never** written to disk, exports, logs, or session files.
- Each key is sent **only** to that provider's own endpoint, over HTTPS. Local backends — Ollama and your own OpenAI-compatible servers — go wherever you point them, which is `localhost` unless you change it in Settings.
- You pay the providers directly with your own keys — Council never sits in the middle.

Don't have a key yet? Council links you straight to each provider's console from the key-entry step.

## Install

> **Official downloads come only from this repo's [Releases](../../releases) and the `albertofettucini/council` Homebrew tap.** Look-alike "Council" repos elsewhere on GitHub are not this project. Don't run their downloads.

**Homebrew** — one command:

```sh
brew install --cask albertofettucini/council/council
```

**Or download** the macOS build from the [latest release](../../releases/latest), unzip it, and drag `Council.app` to Applications. Requires **macOS 14 or later**.

> ⚠️ **First launch:** Council isn't signed with a paid Apple certificate (it's a free, solo, open-source project), so macOS blocks it the first time. Open `Council.app` once; when macOS says it "could not verify" the app, click **Done**. Then go to **System Settings → Privacy & Security**, scroll down to **Security**, click **Open Anyway** next to the Council message, and confirm with your password or Touch ID. Do it right away — that button only shows for about an hour after the blocked launch. It opens normally after that. (Still on macOS 14? Right-click `Council.app` → Open works there too.)
>
> Want to skip that step? After installing (Homebrew or download), run `xattr -dr com.apple.quarantine /Applications/Council.app`.
>
> Rather build it yourself? The whole app is in this repo — see [Build from source](#build-from-source).

### Build from source

```sh
git clone https://github.com/albertofettucini/Council.git
cd Council
open Council.xcodeproj   # Xcode 26 or later (the Liquid Glass path needs the macOS 26 SDK; the built app still runs on macOS 14+)
# ⌘R to run
```

Three SPM dependencies, all resolved automatically by Xcode: **Sparkle** (in-app updates), **CouncilKit** (the engine — a separate package at [github.com/albertofettucini/CouncilKit](https://github.com/albertofettucini/CouncilKit), shared with the CLI), and **Engram** (only for the optional decision-memory bridge). Otherwise pure SwiftUI + Foundation.

## CLI

The same engine, in your terminal — for scripting, CI, and piping documents in:

```sh
git clone https://github.com/albertofettucini/CouncilKit.git
cd CouncilKit && swift build -c release
cp .build/release/council /usr/local/bin/   # or anywhere on your PATH

council keys set claude                      # keys go to the macOS Keychain (shared with the app)
council "should we ship now or wait?" --seats claude,gpt,gemini
council "review this" --file design.md --md  # attach a document, get a decision memo
cat design.md | council "review this"        # …or pipe it in on stdin
council "..." --guest chatgpt-answer.txt     # seat an outside answer in the blind review
council "..." --chair claude                 # a neutral chair moderates instead of answering
council "..." --json                         # structured output (schema council.cli.v1)
council "..." --fail-above 40                # CI gate: exit 1 if the council diverges too much
```

CLI runs land in the app's history, so you can reopen them in the UI. `council --help` has the full flag list.

## A typical question

> *"Should a two-person startup adopt microservices on day one?"*

In the recorded run, Claude, GPT and a local Ollama model all say no: start with a modular
monolith. Each one reviews the other two blind, the score shows how close they landed, and the
dissent card still puts Ollama's answer in front of you, because its "no" leaves more room for
exceptions than the other two. Synthesis hands you a decision-ready summary.

This exact question is the example council inside the app. Open it from the welcome card, or from Home until your first session, to see the full run: answers, blind review, the score and the dissent.

## Roadmap

- More local backends out of the box
- Recall past decisions when a new question resembles an old one

## Contributing

Issues and PRs welcome. Council is one person's project — keep changes focused and the
privacy guarantees intact: no telemetry, and keys never leave the Keychain.

## Contact

Questions, ideas, or feedback? Open an issue — or reach me at **joseph.thecouncil@gmail.com**.

## More from the same maker

[**Engram**](https://github.com/albertofettucini/Engram) — one shared, local memory for all your AIs. Import your ChatGPT/Claude history once; every MCP client can recall it.

## License

[MIT](LICENSE) © 2026 Joseph

---

<p align="center"><sub>Made for people who'd rather weigh a few good opinions than trust one.</sub></p>
