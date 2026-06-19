import Foundation

// MARK: - CouncilKit public facade
//
// A small, stable front door over the Council engine: describe a panel of advisors, ask one
// question, get back a structured `DeliberationResult` — or `stream(...)` it live. This is a THIN
// WRAPPER over `CouncilStore`; it adds no behaviour, it just packages the existing pipeline
// (answers → blind peer review → divergence → synthesis) behind a clean, documented API. The richer
// `CouncilStore` stays public for the app / CLI; external adopters only need what's in this file.
//
// The public API is NOT MainActor-bound — call it from any task or actor. The engine (`CouncilStore`)
// is `@MainActor`, so the facade hops to the MainActor internally and hands back `Sendable` values.
// API keys come from the macOS Keychain by default (zero config), or directly in code via
// `Advisor(apiKey:)` / `Council(keyProvider:)`. A facade call LEAVES NO TRACE: it runs on its own
// non-persisting store and writes nothing to disk, UserDefaults, or the Keychain — direct keys and
// custom endpoints are held in memory only, for that call.

/// The model provider behind an advisor (Claude, GPT, Gemini, DeepSeek, Grok, Mistral, Perplexity,
/// OpenRouter, Ollama, on-device, or a custom OpenAI-compatible endpoint). Alias of the engine's
/// provider enum so there's a single source of truth.
public typealias Backend = LLMProvider

extension LLMProvider: @unchecked Sendable {}   // an immutable enum; safe to pass across actors

public extension LLMProvider {
    /// Friendly alias — `.gpt` reads better than `.openAI` at the call site.
    static var gpt: LLMProvider { .openAI }
}

/// The lens an advisor argues from. The built-ins map to Council's debate personas; `.custom`
/// supplies your own system prompt for that advisor.
public enum Persona: Sendable {
    case analyst, practitioner, skeptic, devilsAdvocate
    case custom(String)

    @MainActor var systemPrompt: String {   // the built-in prompts are MainActor-isolated on CouncilStore
        switch self {
        case .analyst:        return CouncilStore.personaAnalyst
        case .practitioner:   return CouncilStore.personaPractitioner
        case .skeptic:        return CouncilStore.personaSkeptic
        case .devilsAdvocate: return Self.devilsAdvocatePrompt
        case .custom(let p):  return p
        }
    }

    private static let devilsAdvocatePrompt = """
    You are the council's devil's advocate. Argue the strongest case AGAINST the obvious or popular \
    answer: surface the overlooked risks, the failure modes, and the best case for the opposite \
    conclusion. Be specific and intellectually honest — if the popular view genuinely holds, say \
    exactly what would have to be true for it to be wrong. Do not soften your critique to be agreeable.
    """
}

/// One advisor at the table: a backend, the persona it argues from, an optional model override
/// (`nil` uses the backend's default), an optional API key supplied directly in code (`nil` falls
/// back to `Council(keyProvider:)` then the Keychain), and — for `.custom1`/`.custom2` — an optional
/// base URL for a custom OpenAI-compatible server (held transiently for the call; never persisted).
public struct Advisor: Sendable {
    public var backend: Backend
    public var persona: Persona
    public var model: String?
    public var apiKey: String?
    public var endpoint: URL?
    public init(backend: Backend, persona: Persona = .analyst, model: String? = nil,
                apiKey: String? = nil, endpoint: URL? = nil) {
        self.backend = backend
        self.persona = persona
        self.model = model
        self.apiKey = apiKey
        self.endpoint = endpoint
    }
}

/// A live event from `stream(...)`.
public enum DeliberationEvent: Sendable {
    /// A chunk of an advisor's answer as it arrives.
    case token(advisor: String, text: String)
    /// An advisor dropped out (no key / network / provider error). NON-terminal — the run continues
    /// with the advisors that answered.
    case advisorFailed(advisor: String, error: String)
    /// An advisor's completed blind peer-review critique.
    case critique(advisor: String, text: String)
    /// The divergence verdict — score, camps, outlier, and the narrative.
    case divergence(DeliberationResult.Divergence)
    /// The final decision-ready synthesis.
    case synthesis(String)
    /// Setup or no-answer failure (the streamed equivalent of `deliberate(...)` throwing). Terminal.
    case failure(CouncilError)
}

/// Everything a finished deliberation hands back.
public struct DeliberationResult: Sendable {
    /// One advisor's independent answer and the blind critique it contributed in peer review.
    public struct Answer: Sendable {
        public let backend: String
        public let text: String
        public let peerReview: String?
    }
    /// How far apart the council landed — `score` 0 (identical) … 100 (poles apart) — plus how many
    /// camps formed, which advisor was the outlier, and the human-readable analysis. Measures
    /// agreement, not correctness.
    public struct Divergence: Sendable {
        public let score: Int
        public let camps: Int?
        public let outlier: String?
        public let analysis: String?
    }
    /// The outlier's full answer, spotlighted on its own.
    public struct Dissent: Sendable { public let advisor: String; public let answer: String }
    /// An advisor that didn't answer (no key / network / provider error). The deliberation still ran
    /// over the advisors that did.
    public struct FailedAdvisor: Sendable { public let backend: String; public let error: String }
    /// Spend for this deliberation. `inputTokens`/`outputTokens` are REAL provider usage and the
    /// stable primitive; `usd` is an ESTIMATE from built-in per-(backend, model) prices that can go
    /// stale — supply `Council(pricing:)` to override, or compute your own from the token counts.
    public struct Cost: Sendable { public let usd: Double; public let inputTokens: Int; public let outputTokens: Int }

    public let answers: [Answer]
    public let synthesis: String?              // nil unless at least two advisors answered
    public let divergence: Divergence?         // nil unless at least two advisors answered
    public let dissent: Dissent?               // nil if there was no clear outlier
    public let failedAdvisors: [FailedAdvisor] // advisors that errored; empty if all answered
    public let cost: Cost
}

public enum CouncilError: Error, Sendable {
    case noAdvisors
    case tooManyAdvisors(max: Int)
    case missingAPIKeys      // none of the chosen backends has a key (in code or in the Keychain)
    case noAdvisorAnswered   // every seat errored (no key / network / provider failure)
}

/// Override the per-(backend, model) prices used for `result.cost.usd` (the built-ins can go stale).
/// Returns ($/1M input, $/1M output); `nil` ⇒ use the built-in price. `model` is the model id the
/// usage was billed against (nil if the backend's default was used).
public typealias PriceProvider = @Sendable (Backend, _ model: String?) -> (inputPer1M: Double, outputPer1M: Double)?

/// A council of AI advisors. Build it with a lineup, then `deliberate(...)` or `stream(...)`.
/// Callable from any task or actor — the facade hops to the MainActor internally.
///
/// ```swift
/// let council = Council(advisors: [
///     Advisor(backend: .claude, persona: .analyst),
///     Advisor(backend: .gpt,    persona: .practitioner),
///     Advisor(backend: .gemini, persona: .skeptic),
/// ])
/// let result = try await council.deliberate("Should a two-person startup adopt microservices on day one?")
/// print(result.synthesis ?? "")
/// print("divergence:", result.divergence?.score ?? 0)
/// ```
public struct Council: Sendable {
    public var advisors: [Advisor]
    /// Resolves a key for a backend when an `Advisor` doesn't carry its own. `nil` result ⇒ fall back
    /// to the Keychain (the zero-config default).
    public var keyProvider: (@Sendable (Backend) -> String?)?
    /// Override the prices used for `result.cost.usd`. See `PriceProvider`.
    public var pricing: PriceProvider?

    public init(advisors: [Advisor],
                keyProvider: (@Sendable (Backend) -> String?)? = nil,
                pricing: PriceProvider? = nil) {
        self.advisors = advisors
        self.keyProvider = keyProvider
        self.pricing = pricing
    }

    /// Save an API key for a backend into the macOS Keychain (shared with the Council app and CLI).
    /// Keys never leave the Keychain and are sent only to that provider's endpoint. This PERSISTS —
    /// for a no-trace, in-code key use `Advisor(apiKey:)` / `Council(keyProvider:)` instead.
    public static func setKey(_ key: String, for backend: Backend) throws {
        try KeychainStore.save(key, account: backend.keychainAccount)
    }

    /// Put one question to the whole council and run the full pipeline
    /// (answers → blind peer review → divergence → synthesis). Optionally attach a document every
    /// advisor reads first. Nothing is persisted.
    ///
    /// Tolerant of partial failure: advisors that error (no key / network / provider failure) are
    /// dropped and listed in `result.failedAdvisors`; the run proceeds over the rest. Peer review /
    /// divergence / synthesis run only when at least two advisors answered — otherwise `synthesis` and
    /// `divergence` are `nil`. Throws `.missingAPIKeys` if no advisor has a key, `.noAdvisorAnswered`
    /// if every advisor errored.
    public func deliberate(_ question: String, document: String? = nil) async throws -> DeliberationResult {
        try await Self.runDeliberation(advisors, question: question, document: document,
                                       keyProvider: keyProvider, pricing: pricing)
    }

    /// The same deliberation, streamed live: answer tokens per advisor, any `advisorFailed`, then each
    /// critique, the divergence verdict, and the synthesis — as they're produced. A setup or no-answer
    /// failure arrives as a terminal `.failure` event.
    public func stream(_ question: String, document: String? = nil) -> AsyncStream<DeliberationEvent> {
        let advisors = advisors, keyProvider = keyProvider, pricing = pricing
        return AsyncStream { continuation in
            let task = Task { @MainActor in
                let run = StreamRun(advisors: advisors, question: question, document: document,
                                    keyProvider: keyProvider, pricing: pricing, continuation: continuation)
                await run.go()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: Engine plumbing — MainActor-isolated (the engine is @MainActor); returns Sendable values.

    @MainActor
    private static func runDeliberation(_ advisors: [Advisor], question: String, document: String?,
                                        keyProvider: (@Sendable (Backend) -> String?)?,
                                        pricing: PriceProvider?) async throws -> DeliberationResult {
        let store = try configuredStore(advisors, keyProvider: keyProvider, pricing: pricing)
        await store.ask(question, document: document)
        guard let answered = round(store), !answered.answeredSeatIDs.isEmpty else {
            throw CouncilError.noAdvisorAnswered
        }
        if store.canPeerReview {                 // the engine's own predicate: ≥2 keyed seats answered, none loading
            await store.peerReview()
            await store.runDivergence()
            await store.runSynthesis()
        }
        return result(store)
    }

    @MainActor
    static func configuredStore(_ advisors: [Advisor],
                                keyProvider: (@Sendable (Backend) -> String?)? = nil,
                                pricing: PriceProvider? = nil) throws -> CouncilStore {
        guard !advisors.isEmpty else { throw CouncilError.noAdvisors }
        let store = CouncilStore()
        store.persistenceEnabled = false      // a library call never touches the app's saved history or lineup
        store.refreshKeyCache()               // warm the Keychain cache (the app does this on launch; a
                                              // fresh store's `hasKey` would otherwise read empty)
        store.newSession()
        store.priceOverride = pricing         // nil ⇒ built-in prices
        // Isolate from any persisted app state. CouncilStore.init() loads these from UserDefaults, and they
        // change behaviour (which seat plays devil's advocate in peer review, which seat authors the
        // synthesis, per-seat sampling). Persistence is gated above, so these resets don't write back.
        store.devilsAdvocateSeatID = -1       // the facade expresses devil's-advocate via the answer Persona
        store.synthesizerSeatID = -1          // auto: the first connected seat authors divergence/synthesis
        guard advisors.count <= store.seats.count else { throw CouncilError.tooManyAdvisors(max: store.seats.count) }
        let seatIDs = store.seats.map(\.id)
        for (i, advisor) in advisors.enumerated() {
            let sid = seatIDs[i]
            store.setProvider(advisor.backend, seatID: sid)
            if let m = advisor.model, !m.isEmpty { store.setModel(m, seatID: sid) }
            store.setSeatPrompt(advisor.persona.systemPrompt, seatID: sid)
            store.setTemperature(nil, seatID: sid)   // ignore any persisted per-seat sampling overrides
            store.setMaxTokens(nil, seatID: sid)
            if let key = advisor.apiKey ?? keyProvider?(advisor.backend), !key.isEmpty {
                store.transientKeys[sid] = key           // direct key wins over the Keychain (no disk)
            }
            if let ep = advisor.endpoint, let chat = LLMProvider.chatEndpoint(forHost: ep.absoluteString) {
                store.transientCustomEndpoints[sid] = chat   // custom endpoint held in memory (no disk)
            }
        }
        for i in advisors.count..<seatIDs.count { store.clearProvider(seatID: seatIDs[i]) }
        guard store.seats.contains(where: { store.hasKey($0) }) else { throw CouncilError.missingAPIKeys }
        return store
    }

    @MainActor
    static func round(_ store: CouncilStore) -> Round? {
        store.rounds.indices.contains(store.viewingRound) ? store.rounds[store.viewingRound] : nil
    }

    /// A stable display name for a seat. Uses the provider's short `panelName` so a seat reads the same
    /// during token streaming (before the engine records `answerProviders`) and afterwards.
    @MainActor
    static func advisorName(_ store: CouncilStore, _ seat: Seat) -> String {
        round(store)?.answerProviders[seat.id] ?? seat.provider?.panelName ?? "Advisor"
    }

    @MainActor
    static func divergence(_ store: CouncilStore) -> DeliberationResult.Divergence? {
        // The engine stores an AGREEMENT score; user-facing divergence is its complement (as the CLI shows).
        store.agreementScore.map {
            .init(score: 100 - $0, camps: store.divergenceCamps, outlier: store.outlierName, analysis: store.divergenceText)
        }
    }

    /// Advisors whose seat ended in a `.failed` state (no key / network / provider error).
    @MainActor
    static func failedAdvisors(_ store: CouncilStore) -> [DeliberationResult.FailedAdvisor] {
        store.seats.compactMap { seat in
            guard case .failed(let msg) = store.status[seat.id] ?? .idle else { return nil }
            return .init(backend: advisorName(store, seat), error: msg)
        }
    }

    @MainActor
    static func result(_ store: CouncilStore) -> DeliberationResult {
        let r = round(store)
        let answers: [DeliberationResult.Answer] = store.seats.compactMap { seat in
            guard let text = r?.answers[seat.id], !text.isEmpty else { return nil }
            let review = r?.peerReviews[seat.id].flatMap { $0.isEmpty ? nil : $0 }
            return .init(backend: advisorName(store, seat), text: text, peerReview: review)
        }
        let dissent: DeliberationResult.Dissent? = {
            guard let name = store.outlierName, let ans = store.outlierAnswer, !ans.isEmpty else { return nil }
            return .init(advisor: name, answer: ans)
        }()
        let cost = DeliberationResult.Cost(usd: r?.costUSD ?? 0,
                                           inputTokens: r?.inputTokens ?? 0,
                                           outputTokens: r?.outputTokens ?? 0)
        return .init(answers: answers, synthesis: store.synthesisText,
                     divergence: divergence(store), dissent: dissent,
                     failedAdvisors: failedAdvisors(store), cost: cost)
    }
}

/// Drives one `stream(...)`: runs the pipeline while polling the (@Observable) store for answer-token
/// deltas, then emits each completed stage. MainActor-isolated, so its mutable run-state is safe to
/// share between the pipeline task and the polling task.
@MainActor
private final class StreamRun {
    let advisors: [Advisor]
    let question: String
    let document: String?
    let keyProvider: (@Sendable (Backend) -> String?)?
    let pricing: PriceProvider?
    let continuation: AsyncStream<DeliberationEvent>.Continuation
    var emitted: [Int: String] = [:]    // the answer text already streamed per seat
    var answersDone = false

    init(advisors: [Advisor], question: String, document: String?,
         keyProvider: (@Sendable (Backend) -> String?)?,
         pricing: PriceProvider?,
         continuation: AsyncStream<DeliberationEvent>.Continuation) {
        self.advisors = advisors
        self.question = question; self.document = document
        self.keyProvider = keyProvider; self.pricing = pricing; self.continuation = continuation
    }

    func go() async {
        defer { continuation.finish() }
        let store: CouncilStore
        do { store = try Council.configuredStore(advisors, keyProvider: keyProvider, pricing: pricing) }
        catch let e as CouncilError { continuation.yield(.failure(e)); return }
        catch { return }

        // Phase A — answers, streamed token-by-token (poll the store while ask() runs concurrently).
        await withTaskGroup(of: Void.self) { group in
            group.addTask { @MainActor [self] in
                await store.ask(question, document: document)
                answersDone = true
            }
            group.addTask { @MainActor [self] in
                while !answersDone && !Task.isCancelled {
                    emitTokens(store)
                    try? await Task.sleep(nanoseconds: 40_000_000)   // ~25 fps
                }
            }
        }
        emitTokens(store)   // final flush

        // Surface advisors that dropped out (non-terminal — the run continues with the survivors).
        for seat in store.seats {
            if case .failed(let msg) = store.status[seat.id] ?? .idle {
                continuation.yield(.advisorFailed(advisor: Council.advisorName(store, seat), error: msg))
            }
        }

        // Phase B — deliberation. Each stage is emitted once, complete.
        guard let answered = Council.round(store), !answered.answeredSeatIDs.isEmpty else {
            continuation.yield(.failure(.noAdvisorAnswered)); return
        }
        guard store.canPeerReview, !Task.isCancelled else { return }

        await store.peerReview()
        if let r = Council.round(store) {
            for seat in store.seats {
                if let rv = r.peerReviews[seat.id], !rv.isEmpty {
                    continuation.yield(.critique(advisor: Council.advisorName(store, seat), text: rv))
                }
            }
        }
        if !Task.isCancelled {
            await store.runDivergence()
            if let d = Council.divergence(store) { continuation.yield(.divergence(d)) }
        }
        if !Task.isCancelled {
            await store.runSynthesis()
            if let s = store.synthesisText, !s.isEmpty { continuation.yield(.synthesis(s)) }
        }
    }

    private func emitTokens(_ store: CouncilStore) {
        guard let r = Council.round(store) else { return }
        for seat in store.seats {
            let full = r.answers[seat.id] ?? ""
            let prev = emitted[seat.id] ?? ""
            guard full.count > prev.count else { continue }
            // The engine stores the cumulative answer-so-far, so the new tail is the suffix after the
            // common prefix. commonPrefix is grapheme-aware, so a multi-scalar cluster split across SSE
            // chunks resyncs instead of double-emitting.
            let tail = full.hasPrefix(prev) ? String(full.dropFirst(prev.count))
                                            : String(full.dropFirst(full.commonPrefix(with: prev).count))
            continuation.yield(.token(advisor: Council.advisorName(store, seat), text: tail))
            emitted[seat.id] = full
        }
    }
}
