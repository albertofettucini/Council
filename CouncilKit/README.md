<p align="center">
  <img src="docs/icon.png" width="120" alt="CouncilKit">
</p>

<h1 align="center">CouncilKit</h1>

<p align="center">
  <b>Multi-model deliberation as a Swift primitive.</b><br>
  Put one question to several LLMs, let them critique each other blind, and get back a decision —
  with a disagreement score and the dissenting view surfaced.<br>
  Because one model gives you one model's blind spots.
</p>

<p align="center">
  <img alt="Swift 6" src="https://img.shields.io/badge/Swift-6-orange">
  <img alt="SPM" src="https://img.shields.io/badge/SPM-compatible-brightgreen">
  <img alt="Platform" src="https://img.shields.io/badge/platform-macOS%2014%2B-lightgrey">
  <img alt="License: MIT" src="https://img.shields.io/badge/License-MIT-blue">
</p>

## Why

Asking one model a hard question gives you one model's confidence — including the spots where it's
confidently wrong. For anything that actually matters (a design call, a risk assessment, an
irreversible decision), you want a panel: several models answer independently, critique each other
without brand bias, and tell you where they disagree.

CouncilKit is that panel — a **macOS** library you drop into your own app, agent, or CI pipeline. It's
the engine behind [Council](https://github.com/albertofettucini/Council) — now standalone.

## Install

Swift Package Manager:

```swift
.package(url: "https://github.com/albertofettucini/CouncilKit.git", .upToNextMinor(from: "0.1.0"))
```

Then `import CouncilKit`. **Pre-1.0** — the API may change before 1.0, so pin to an exact minor
(`.upToNextMinor`) rather than letting SPM float to a breaking 0.x.

## 30-second example

```swift
import CouncilKit

// Three advisors: each a backend + a persona, for real divergence.
let council = Council(advisors: [
    Advisor(backend: .claude, persona: .analyst),
    Advisor(backend: .gpt,    persona: .practitioner),
    Advisor(backend: .gemini, persona: .skeptic),
])

let result = try await council.deliberate(
    "Should a two-person startup adopt microservices on day one?"
)

print(result.synthesis ?? "")        // decision-ready distillation
print(result.divergence?.score ?? 0) // 0–100: how far apart they landed
print(result.dissent?.answer ?? "")  // the outlier's full case, if there is one
```

That's the whole loop: parallel answers → blind peer review → divergence → synthesis, with the
outlier kept visible so the majority can't quietly be wrong together.

## What you get back

- `synthesis` — a decision-ready distillation of where the council netted out.
- `divergence` — a 0–100 read of how far apart the answers landed, the camps that formed, who the outlier is, and the written analysis. It measures agreement, not correctness.
- `dissent` — the outlier's full answer, on its own, because consensus isn't proof.
- `answers` — every advisor's original answer and the blind critique it wrote.
- `failedAdvisors` — advisors that errored (no key / network / provider failure). The run proceeds over the rest, so a partial result is never silently mistaken for a smaller council.
- `cost` — real `inputTokens` / `outputTokens` (the stable primitive) plus a `usd` estimate from built-in prices (overridable via `Council(pricing:)`).

## Core ideas

- **Blind peer review** — each advisor critiques the others without knowing who wrote what. No brand bias, just the argument.
- **Personas** — `.analyst`, `.practitioner`, `.skeptic`, `.devilsAdvocate` (or `.custom("…")`) — so you get real divergence, not three ways of saying the same thing.
- **Streaming** — stream tokens per advisor as they arrive, then each stage as it completes.

```swift
for await event in council.stream("…") {
    switch event {
    case .token(let advisor, let text):    break  // live answer, per advisor
    case .advisorFailed(let advisor, let error): break  // an advisor dropped out (non-terminal)
    case .critique(let advisor, let text): break  // blind peer review
    case .divergence(let report):          break  // report.score / .camps / .outlier / .analysis
    case .synthesis(let text):             break  // final distillation
    case .failure(let error):              break  // setup / no-answer failure (terminal)
    }
}
```

## Backends — bring your own keys

Claude · GPT (OpenAI) · Gemini · DeepSeek · Grok (xAI) · Mistral · Perplexity · OpenRouter ·
Ollama (local) · Apple Intelligence (on-device) · plus two custom OpenAI-compatible endpoints
(llama.cpp, LM Studio, vLLM, a second Ollama box…).

By default keys come from the **macOS Keychain** (zero config) and are sent only to each provider's own
endpoint over HTTPS (Ollama stays on `localhost`). CouncilKit never stores keys anywhere else and never
sits between you and the provider — you pay the providers directly. No telemetry.

```swift
try Council.setKey("sk-…", for: .claude)        // → Keychain (shared with the Council app & CLI)
```

Or pass keys directly in code — handy off macOS, in CI, or with your own secrets store:

```swift
let council = Council(
    advisors: [Advisor(backend: .claude, persona: .analyst, apiKey: claudeKey)],
    keyProvider: { backend in myVault[backend] }   // used when an Advisor has no apiKey; nil ⇒ Keychain
)
```

Point an advisor at any OpenAI-compatible server (llama.cpp, LM Studio, vLLM, …) — the endpoint and
its key are held transiently for the call, never written to disk or Keychain:

```swift
let advisor = Advisor(backend: .custom1, model: "my-model",
                      apiKey: serverKey,                        // optional — some servers need auth
                      endpoint: URL(string: "http://localhost:8080")!)
```

## CLI

The same engine in your terminal — for scripting and CI:

```sh
council "should we ship now or wait?" --seats claude,gpt,gemini
council "review this" --file design.md --json     # structured output (schema council.cli.v1)
cat design.md | council "review this"             # …or pipe it in on stdin
council "..." --fail-above 40                      # exit 1 if the council diverges too much
```

Gate a PR on disagreement, pipe a document in, get JSON out.

## Requirements

- Swift 5.9+ toolchain (verified on Swift 6.3), macOS 14+
- Network access for hosted backends (local backends run fully offline)

## Status & notes

Pre-1.0, solo project — issues welcome, best-effort support, no SLA. The API may still change before 1.0.

Not affiliated with the model providers; product names are trademarks of their respective owners.

<sub>Keywords: multi-model · llm-ensemble · consensus · llm-as-judge · peer-review · verification · llm · swift · spm</sub>

## License

[MIT](LICENSE) © 2026 Joseph

<p align="center"><sub>Don't trust one model. Convene a few.</sub></p>
