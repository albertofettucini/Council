import Foundation
import Observation
import AppKit
import UserNotifications

/// Per-seat live state (applies to the round currently being generated).
public enum SeatStatus: Equatable { case idle, loading, failed(String) }

/// Result of a "test connection" probe against a local/self-hosted endpoint (Settings → Models).
public enum EndpointTestResult: Equatable { case ok(Int); case failed(String) }

/// Shared engine limits, owned here so every surface (app, CLI, future MCP) enforces the same rule.
public enum CouncilLimits {
    /// Conservative cap for an attached document, in characters (~25k tokens). Past this, surfaces
    /// must REJECT with a clear error — never silently truncate.
    public static let maxDocumentCharacters = 100_000
    /// nil if the document is within the cap, else a clear, specific error message.
    public static func documentError(_ text: String) -> String? {
        let n = text.count
        guard n > maxDocumentCharacters else { return nil }
        return "Document is \(n) characters — the limit is \(maxDocumentCharacters). Trim it or paste a smaller excerpt."
    }
}

/// Central app state. A session is a list of `Round`s; each round keeps its own answers,
/// peer reviews, divergence and synthesis. The user navigates rounds; nothing is wiped.
@MainActor
@Observable
public final class CouncilStore {
    public var seats: [Seat]
    public var status: [Int: SeatStatus] = [:]
    /// All rounds in the current session, oldest → newest.
    public var rounds: [Round] = []
    /// Which round the UI is showing (analyses + answers are read from this round).
    public var viewingRound = 0
    /// True while a divergence/synthesis round is running.
    public var deliberationBusy = false
    /// CLI `--no-save`: when false, finished sessions are not written to disk. Always true in the app.
    public var persistenceEnabled = true
    /// Human-readable stage the auto-pipeline is generating right now (nil = idle).
    /// Drives the flow page's quiet inline progress hint.
    public var pipelineStage: String?
    /// Which round index is currently generating answers/peer-reviews (nil = none). The panel
    /// spinner keys off this so it shows on the round actually working, not just the latest.
    public var generatingRound: Int?
    /// Transient (NEVER persisted) error from the last divergence / synthesis attempt. We never
    /// write an error string into a round's content — a failed network call must not become
    /// permanent "analysis" saved to disk. Shown briefly in the canvas, cleared on retry/nav.
    public var divergenceError: String?
    public var synthesisError: String?
    /// Bumped whenever a key is saved; refreshes the key cache so views re-evaluate `hasKey`.
    public var keyRevision = 0 { didSet { refreshKeyCache() } }
    /// Cached set of providers that currently have a key — so `hasKey`/`keyExists` never hit the
    /// Keychain from a view body (12 synchronous Keychain reads per render = the scroll jank).
    /// Rebuilt only when a key actually changes, not on every render.
    private(set) var keyCache: Set<LLMProvider> = []
    public func refreshKeyCache() {
        var s: Set<LLMProvider> = []
        for p in LLMProvider.allCases where p.requiresAPIKey {
            if let k = (try? KeychainStore.read(account: p.keychainAccount)) ?? nil, !k.isEmpty { s.insert(p) }
        }
        keyCache = s
    }

    /// Live model lists fetched per provider: Ollama's installed models (/api/tags), OpenRouter's
    /// public catalogue (/models), and any keyed provider's accessible models (/models with the key).
    /// Drives the picker so it offers what the user can actually use; empty for a provider falls back
    /// to that provider's fixed suggestion list.
    public var providerModels: [LLMProvider: [String]] = [:]

    public func refreshModels(for provider: LLMProvider) async {
        guard let url = provider.modelsEndpoint else { return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 6
        // Ollama + custom servers need no auth; OpenRouter's list is public (send a key only if we
        // have one); every other keyed provider needs its key to list what it can actually reach.
        switch provider {
        case .ollama, .custom1, .custom2:
            break
        case .claude:
            guard let k = storedKey(for: provider) else { return }
            req.setValue(k, forHTTPHeaderField: "x-api-key")
            req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        case .openRouter:
            if let k = storedKey(for: provider) { req.setValue("Bearer \(k)", forHTTPHeaderField: "Authorization") }
        default:
            guard let k = storedKey(for: provider) else { return }
            req.setValue("Bearer \(k)", forHTTPHeaderField: "Authorization")
        }
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { return }
            let ids = Self.parseModelList(data)
            if !ids.isEmpty, ids != providerModels[provider] { providerModels[provider] = ids }
        } catch {
            // Unreachable / no key — keep whatever we have; the picker falls back to suggestions.
        }
    }

    /// Explicit "test connection" for a local/self-hosted endpoint (Ollama or a custom slot —
    /// Settings → Models). Unlike refreshModels, it reports a result the UI can show, and on
    /// success seeds providerModels so the picker immediately shows the server's real models.
    public func testEndpoint(for provider: LLMProvider) async -> EndpointTestResult {
        guard let url = provider.modelsEndpoint else { return .failed("Set a valid URL first.") }
        var req = URLRequest(url: url); req.timeoutInterval = 6
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else { return .failed("No response from that address.") }
            guard http.statusCode == 200 else { return .failed("Reached it, but it returned HTTP \(http.statusCode).") }
            let ids = Self.parseModelList(data)
            if !ids.isEmpty { providerModels[provider] = ids }
            return .ok(ids.count)
        } catch {
            let host = provider.customSlot.map(LLMProvider.customHost) ?? LLMProvider.ollamaHost
            return .failed("Couldn't reach \(host) — is the server running and reachable from this Mac?")
        }
    }

    private func storedKey(for provider: LLMProvider) -> String? {
        guard let k = (try? KeychainStore.read(account: provider.keychainAccount)) ?? nil, !k.isEmpty else { return nil }
        return k
    }

    /// Both shapes we encounter: OpenAI-style `{"data":[{"id":…}]}` and Ollama `{"models":[{"name":…}]}`.
    private static func parseModelList(_ data: Data) -> [String] {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        if let arr = obj["data"] as? [[String: Any]] { return arr.compactMap { $0["id"] as? String }.sorted() }
        if let arr = obj["models"] as? [[String: Any]] { return arr.compactMap { $0["name"] as? String }.sorted() }
        return []
    }

    /// Full per-seat conversation (user/assistant turns, no system). Replayed on Round 1 calls
    /// so each model has its own prior context across rounds.
    private var history: [Int: [ChatMessage]] = [:]

    /// Shared Round-1 system prompt — the "advisor" instruction, user-editable. A seat can
    /// override it (see `Seat.systemPrompt`). Persisted in UserDefaults (non-sensitive).
    public var sharedSystemPrompt: String = CouncilStore.defaultSystemPrompt {
        didSet { UserDefaults.standard.set(sharedSystemPrompt, forKey: Self.promptKey) }
    }

    /// Which seat generates divergence + synthesis (and so spends that provider's credit). Persisted.
    public var synthesizerSeatID: Int = 0 {
        didSet { guard persistenceEnabled else { return }; UserDefaults.standard.set(synthesizerSeatID, forKey: Self.synthKey) }
    }

    /// Which seat (if any) plays devil's advocate — in peer review it steelmans then attacks the
    /// emerging consensus instead of looking for agreement. -1 = none. Persisted.
    public var devilsAdvocateSeatID: Int = -1 {
        didSet { guard persistenceEnabled else { return }; UserDefaults.standard.set(devilsAdvocateSeatID, forKey: Self.devilKey) }
    }

    private let seatsKey = "council.seats.v7"   // v7: ship default divergence personas
    private static let promptKey = "council.systemPrompt"
    private static let synthKey = "council.synthesizerSeat"
    private static let devilKey = "council.devilsAdvocate"
    public static let defaultSystemPrompt =
        "You are one of several AI advisors on a council. Answer the user's question directly, clearly, and concisely, in your own voice. Be honest; never flatter."

    /// Default per-seat personas. Three GENERAL-PURPOSE lenses (not domain-specific) so the council
    /// genuinely diverges on any non-trivial question out of the box — each still gives a complete
    /// answer, just from a different angle. Users can edit or clear these in Settings.
    public static let personaAnalyst = """
    You are the analyst on a council of advisors. Reason from first principles: name the core \
    variables, state your assumptions, and show the logic that leads to your answer. Give a \
    complete, well-structured answer to the user's question, and be honest about tradeoffs and \
    uncertainty — if the real answer is "it depends," say exactly what it depends on. Don't hedge \
    to sound agreeable. Be concise and in your own voice.
    """
    public static let personaPractitioner = """
    You are the practitioner on a council of advisors. Answer from real-world experience: what \
    actually happens in practice, the second-order effects, the practical constraints, and what \
    most people get wrong. Give a complete, decisive answer to the user's question, grounded in how \
    this plays out for real, and prefer concrete specifics over abstractions. Be concise and in \
    your own voice; no flattery.
    """
    public static let personaSkeptic = """
    You are the skeptic on a council of advisors. Challenge the easy answer: question the framing, \
    surface the strongest counter-case, and name the risks and failure modes the others will likely \
    miss. Still give a complete answer to the user's question — take the position you actually find \
    most defensible, even if it's unpopular — but make the costs and downsides explicit. Be specific \
    and intellectually honest, never contrarian just for show. Concise, in your own voice.
    """

    private static let peerReviewPrompt = """
    You are one of three AI advisors on a council and you have already given your own answer. \
    Below are the other advisors' answers to the same question, anonymized. Review them critically: \
    state clearly where you AGREE and where you DISAGREE, and why. If one of them changed your mind, \
    say so and refine your view. If you still disagree, hold your ground and explain — do NOT cave to \
    consensus just to agree. Be concise, honest, and in your own voice.
    """

    private static let adversaryReviewPrompt = """
    You are the council's Devil's Advocate. Your job is NOT to find agreement — it is to stress-test \
    the emerging consensus. First steelman the position the other advisors seem to share: state it in \
    its strongest, fairest form. Then attack it — surface the strongest objections, the overlooked \
    risks, the failure modes, and the best case for the opposite conclusion. Be specific and \
    intellectually honest: if the consensus genuinely survives scrutiny, say exactly what would have \
    to be true for it to be wrong. Do NOT soften your critique just to be agreeable.
    """

    private static let divergencePrompt = """
    You are the council's analyst. You are given the advisors' answers to a question. Map the \
    deliberation in two clearly-headed markdown sections: "## Agreement" (points most or all advisors \
    share) and "## Divergence" (where they disagree — name which advisor holds which view, and why). \
    Be specific and concise. Do NOT pick a winner; just map the landscape honestly.
    """

    /// Tiny structured-verdict prompt, run as a SEPARATE json-mode call (reliable even on small local
    /// models) so the score never depends on a free-form line the model might drop.
    private static let verdictPrompt = """
    You are a meticulous judge. Given the advisors' answers, output ONLY a JSON object and nothing else:
    {"agreement": <integer 0-100, how much they agree on the bottom-line conclusion>, "camps": <integer number of distinct positions>, "outlier": <the single advisor label most apart, e.g. "Advisor B", or null>}
    Agreement measures consensus, not correctness.
    """

    private static let synthesisPrompt = """
    You are the council's synthesizer. Given the advisors' answers, produce a \
    final synthesis in markdown with two parts: a clear, decisive recommended answer first; then a \
    section "## Where they diverged" that explicitly preserves the dissent — note where advisors \
    disagreed and why, without flattening it into false consensus. The human decides: give them a \
    clear map, not a command.
    """

    public init() {
        if let data = UserDefaults.standard.data(forKey: seatsKey),
           let saved = try? JSONDecoder().decode([Seat].self, from: data), saved.count == 3 {
            seats = saved
        } else {
            // Start unassigned (each panel shows PICK YOUR MODEL) but with distinct default
            // personas, so the council genuinely diverges from the very first question.
            seats = [
                Seat(id: 0, archetype: .sage,       systemPrompt: Self.personaAnalyst),
                Seat(id: 1, archetype: .scientist,  systemPrompt: Self.personaPractitioner),
                Seat(id: 2, archetype: .strategist, systemPrompt: Self.personaSkeptic)
            ]
        }
        if let savedPrompt = UserDefaults.standard.string(forKey: Self.promptKey), !savedPrompt.isEmpty {
            sharedSystemPrompt = savedPrompt
        }
        if let n = UserDefaults.standard.object(forKey: Self.synthKey) as? Int { synthesizerSeatID = n }
        if let n = UserDefaults.standard.object(forKey: Self.devilKey) as? Int { devilsAdvocateSeatID = n }
        // Only the APP warms the key cache (it shows all providers' status). A bare CLI process
        // doing this would hit the Keychain for every provider at launch — a wall of permission
        // prompts. The CLI reads lazily, only for seats it actually uses (see keyExists).
        if Bundle.main.bundleIdentifier != nil { refreshKeyCache() }
        loadSessions()
    }

    public func saveSeats() {
        // A non-persisting store (the CouncilKit facade, or `council --no-save`) must not overwrite the
        // app's saved seat lineup. Persistence is gated consistently on persistenceEnabled.
        guard persistenceEnabled else { return }
        if let data = try? JSONEncoder().encode(seats) {
            UserDefaults.standard.set(data, forKey: seatsKey)
        }
    }

    // MARK: - Shareable council config (export / import / presets)

    /// Capture the current setup as a shareable config (no keys — see CouncilConfig).
    public func currentConfig(name: String) -> CouncilConfig {
        let seatConfigs = seats.map { s in
            CouncilConfig.SeatConfig(provider: s.provider, model: s.model,
                                     systemPrompt: s.systemPrompt,
                                     temperature: s.temperature, maxTokens: s.maxTokens)
        }
        let synthIdx = seats.firstIndex { $0.id == synthesizerSeatID }
        let devilIdx = seats.firstIndex { $0.id == devilsAdvocateSeatID }
        return CouncilConfig(name: name.isEmpty ? "My council" : name,
                             seats: seatConfigs,
                             sharedSystemPrompt: sharedSystemPrompt,
                             synthesizerSeatIndex: synthIdx,
                             devilsAdvocateSeatIndex: devilIdx)
    }

    /// Apply a shared/preset config to the live seats. Keeps existing seat ids, maps each
    /// SeatConfig onto a seat by position. Keys are untouched (loaded from Keychain as needed).
    public func applyConfig(_ config: CouncilConfig) {
        for i in seats.indices {
            if let sc = config.seats.indices.contains(i) ? config.seats[i] : nil {
                seats[i].provider = sc.provider
                seats[i].model = sc.model.isEmpty ? (sc.provider?.defaultModel ?? "") : sc.model
                seats[i].systemPrompt = sc.systemPrompt
                // Clamp imported sampling through the same bounds as the manual setters, so a
                // hand-edited/malicious file can't set e.g. maxTokens: 100000000 or temperature: 9.
                seats[i].temperature = sc.temperature.map { min(max($0, 0), 2) }
                seats[i].maxTokens = sc.maxTokens.flatMap { $0 > 0 ? min($0, 64_000) : nil }
            } else {
                // Config specifies fewer seats than we have → clear the trailing ones rather than
                // leaving a stale provider/persona from the previous council.
                seats[i].provider = nil
                seats[i].model = ""
                seats[i].systemPrompt = nil
                seats[i].temperature = nil
                seats[i].maxTokens = nil
            }
        }
        sharedSystemPrompt = config.sharedSystemPrompt.isEmpty ? sharedSystemPrompt : config.sharedSystemPrompt
        if let s = config.synthesizerSeatIndex, seats.indices.contains(s) { synthesizerSeatID = seats[s].id }
        if let d = config.devilsAdvocateSeatIndex, seats.indices.contains(d) { devilsAdvocateSeatID = seats[d].id }
        else { devilsAdvocateSeatID = -1 }
        saveSeats()
        keyRevision += 1
    }

    public func setSeatPrompt(_ prompt: String?, seatID: Int) {
        guard let idx = seats.firstIndex(where: { $0.id == seatID }) else { return }
        seats[idx].systemPrompt = (prompt?.isEmpty == false) ? prompt : nil
        saveSeats()
    }

    // MARK: - Keys

    public var isConfigured: Bool { seats.allSatisfy(hasKey) }

    /// Per-seat API keys supplied directly in code (the CouncilKit facade), consulted BEFORE the
    /// Keychain at request time. Non-persisted — scoped to a single in-memory store.
    public var transientKeys: [Int: String] = [:]

    /// Per-seat custom OpenAI-compatible chat endpoints supplied in code (the CouncilKit facade), used
    /// instead of the persisted `council.custom{N}.host` UserDefaults. Non-persisted — leaves no trace.
    public var transientCustomEndpoints: [Int: URL] = [:]

    public func hasKey(_ seat: Seat) -> Bool {
        if let k = transientKeys[seat.id], !k.isEmpty { return true }   // facade-supplied key
        guard let provider = seat.provider else { return false }   // no model picked yet
        return keyExists(provider)
    }

    public func setKey(_ key: String, for provider: LLMProvider) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try? KeychainStore.save(trimmed, account: provider.keychainAccount)
        keyRevision += 1
    }

    public func clearKey(for provider: LLMProvider) {
        KeychainStore.delete(account: provider.keychainAccount)
        keyRevision += 1
    }

    public func validateAndSaveKey(_ key: String, for seat: Seat) async -> String? {
        guard let provider = seat.provider else { return "No model selected." }
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Empty key." }
        let client = LLMClientFactory.make(for: provider, model: seat.model)
        do { try await client.validate(apiKey: trimmed) } catch { return error.localizedDescription }
        setKey(trimmed, for: provider)
        return nil
    }

    public func setModel(_ model: String, seatID: Int) {
        guard let idx = seats.firstIndex(where: { $0.id == seatID }) else { return }
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        seats[idx].model = trimmed.isEmpty ? (seats[idx].provider?.defaultModel ?? "") : trimmed
        saveSeats()
    }

    /// Assign (or change) a seat's provider, resetting the model to that provider's default.
    public func setProvider(_ provider: LLMProvider, seatID: Int) {
        guard let idx = seats.firstIndex(where: { $0.id == seatID }) else { return }
        seats[idx].provider = provider
        seats[idx].model = provider.defaultModel
        saveSeats()
        keyRevision += 1
    }

    /// Reset a seat back to unassigned ("PICK YOUR MODEL").
    public func clearProvider(seatID: Int) {
        guard let idx = seats.firstIndex(where: { $0.id == seatID }) else { return }
        seats[idx].provider = nil
        seats[idx].model = ""
        saveSeats()
        keyRevision += 1
    }

    /// True if another seat already uses this provider — drives the duplicate-token warning.
    public func providerInUse(_ provider: LLMProvider, excluding seatID: Int) -> Bool {
        seats.contains { $0.id != seatID && $0.provider == provider }
    }

    /// Per-seat sampling override. Passing nil clears it (falls back to provider default).
    public func setTemperature(_ value: Double?, seatID: Int) {
        guard let idx = seats.firstIndex(where: { $0.id == seatID }) else { return }
        seats[idx].temperature = value.map { min(max($0, 0), 2) }   // clamp to a sane range
        saveSeats()
    }

    public func setMaxTokens(_ value: Int?, seatID: Int) {
        guard let idx = seats.firstIndex(where: { $0.id == seatID }) else { return }
        // Treat 0/negative as "no override"; cap very large values to avoid runaway costs.
        if let v = value, v > 0 { seats[idx].maxTokens = min(v, 64_000) }
        else { seats[idx].maxTokens = nil }
        saveSeats()
    }

    // MARK: - Round navigation + viewed accessors

    public var roundCount: Int { rounds.count }
    public var isViewingLatest: Bool { viewingRound >= rounds.count - 1 }
    public var canGoPrevRound: Bool { viewingRound > 0 }
    public var canGoNextRound: Bool { viewingRound < rounds.count - 1 }
    public func prevRound() { if canGoPrevRound { viewingRound -= 1; clearDeliberationErrors() } }
    public func nextRound() { if canGoNextRound { viewingRound += 1; clearDeliberationErrors() } }

    /// Drop the transient divergence/synthesis errors (they belong to one attempt on one round).
    public func clearDeliberationErrors() { divergenceError = nil; synthesisError = nil }

    private var viewedRound: Round? { rounds.indices.contains(viewingRound) ? rounds[viewingRound] : nil }
    public var viewedQuestion: String { viewedRound?.question ?? "" }
    public func viewedAnswer(_ seatID: Int) -> String? { viewedRound?.answers[seatID] }
    public func viewedPeerReview(_ seatID: Int) -> String? { viewedRound?.peerReviews[seatID] }
    /// Provider name recorded for this seat's answer in the viewed round (for the panel title when
    /// the seat itself is currently unassigned, e.g. a reopened session).
    public func viewedAnswerProvider(_ seatID: Int) -> String? { viewedRound?.answerProviders[seatID] }
    /// Read-only views of the current round's cross-model artifacts (used by the UI).
    public var divergenceText: String? { viewedRound?.divergence }
    public var synthesisText: String? { viewedRound?.synthesis }
    /// The verdict's AGREEMENT score (0–100). Named honestly — the UI shows 100 − this as divergence.
    public var agreementScore: Int? { viewedRound?.divergenceScore }
    public var divergenceCamps: Int? { viewedRound?.divergenceCamps }
    public var outlierName: String? { viewedRound?.outlier }
    /// The outlier advisor's own answer for the viewed round — for Dissent. Prefers the seat id
    /// resolved at verdict time; falls back to panel-name matching for sessions saved before that.
    public var outlierAnswer: String? {
        guard let round = viewedRound else { return nil }
        if let sid = round.outlierSeatID, let a = round.answers[sid], !a.isEmpty { return a }
        guard let name = round.outlier,
              let sid = round.answerProviders.first(where: { $0.value == name })?.key,
              let a = round.answers[sid], !a.isEmpty else { return nil }
        return a
    }
    public var hasDissent: Bool { outlierAnswer != nil }

    /// Session token + cost totals (sum across rounds) — an estimate.
    public var sessionInputTokens: Int { rounds.reduce(0) { $0 + $1.inputTokens } }
    public var sessionOutputTokens: Int { rounds.reduce(0) { $0 + $1.outputTokens } }
    public var sessionCostUSD: Double { rounds.reduce(0) { $0 + $1.costUSD } }

    // MARK: Dashboard aggregates (all saved sessions; the current session joins after its first save).
    public var allTimeCostUSD: Double { sessions.reduce(0) { $0 + $1.totalCostUSD } }
    public var thisMonthCostUSD: Double {
        let cal = Calendar.current
        return sessions
            .filter { cal.isDate($0.updatedAt, equalTo: Date(), toGranularity: .month) }
            .reduce(0) { $0 + $1.totalCostUSD }
    }
    /// Most-used model (panel name) across all rounds, for the dashboard's "top model".
    public var topModelName: String? {
        var counts: [String: Int] = [:]
        for s in sessions { for r in s.rounds { for name in r.answerProviders.values { counts[name, default: 0] += 1 } } }
        return counts.max { $0.value < $1.value }?.key
    }
    /// Whether a key exists for this provider — reads the cache, never the Keychain (so it's safe
    /// to call from a view body). Key-free providers (Ollama) are always "ready".
    public func keyExists(_ p: LLMProvider) -> Bool {
        if !p.requiresAPIKey || keyCache.contains(p) { return true }
        // CLI (no bundle): the cache is never warmed — check the Keychain directly, but only
        // when actually asked about this provider (one prompt max, for a seat in use).
        if Bundle.main.bundleIdentifier == nil,
           let k = (try? KeychainStore.read(account: p.keychainAccount)) ?? nil, !k.isEmpty {
            keyCache.insert(p)
            return true
        }
        return false
    }

    // MARK: Spend alert (opt-in local notification when total spend crosses a threshold)
    public static let spendAlertOnKey = "council.spendAlertOn"
    public static let spendAlertAmtKey = "council.spendAlertAmt"
    private static let spendAlertFiredKey = "council.spendAlertFiredAt"

    /// Re-arm the spend alert (called when the user re-enables it or changes the threshold) so a
    /// freshly-configured alert can fire again even if it fired for an earlier threshold.
    public static func rearmSpendAlert() {
        UserDefaults.standard.removeObject(forKey: spendAlertFiredKey)
    }

    /// Fire a one-time local notification when all-time spend first crosses the user's threshold.
    /// Cheap; called from saveConversation so every spend path is covered. No-op unless opted in.
    public func checkSpendAlert() {
        // UNUserNotificationCenter requires a real app bundle — a bare CLI process has none.
        guard Bundle.main.bundleIdentifier != nil else { return }
        let d = UserDefaults.standard
        guard d.bool(forKey: Self.spendAlertOnKey) else { return }
        let threshold = d.double(forKey: Self.spendAlertAmtKey)
        guard threshold > 0, allTimeCostUSD >= threshold,
              d.double(forKey: Self.spendAlertFiredKey) < threshold else { return }
        let spent = allTimeCostUSD
        let firedKey = Self.spendAlertFiredKey   // capture plain Sendable values only (no `self`/`center`)
        // Only burn the one-shot once we KNOW we can actually notify — if authorization was denied,
        // don't set firedAt, so it retries (and fires) once the user grants permission.
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else { return }
            let content = UNMutableNotificationContent()
            content.title = "Council — spend alert"
            content.body = String(format: "You've spent about $%.2f, past your $%.2f alert.", spent, threshold)
            content.sound = .default
            UNUserNotificationCenter.current().add(
                UNNotificationRequest(identifier: "council.spendAlert", content: content, trigger: nil))
            UserDefaults.standard.set(threshold, forKey: firedKey)
        }
    }

    private func answeredSeats(in idx: Int) -> [Seat] {
        guard rounds.indices.contains(idx) else { return [] }
        return seats.filter { hasKey($0) && !((rounds[idx].answers[$0.id] ?? "").isEmpty) }
    }
    private var anyLoading: Bool { status.values.contains { $0 == .loading } || deliberationBusy }
    /// True while any advisor or a deliberation round is generating. The UI uses this to lock
    /// session switching so an in-flight write can't land in a session swapped out underneath it.
    public var isWorking: Bool { anyLoading }
    /// The chosen synthesizer seat if it has a key; otherwise the first connected seat.
    private var synthesizerSeat: Seat? {
        if let chosen = seats.first(where: { $0.id == synthesizerSeatID }), hasKey(chosen) { return chosen }
        return seats.first { hasKey($0) }
    }
    private func canDeliberate(_ idx: Int) -> Bool { answeredSeats(in: idx).count >= 2 && !anyLoading }

    /// Peer review / divergence / synthesis operate on the round you're viewing.
    public var canPeerReview: Bool { canDeliberate(viewingRound) }
    public var canSynthesize: Bool { canDeliberate(viewingRound) }
    /// Whether the viewed round already has peer reviews (so clicking PEER REVIEW just shows them).
    public var hasPeerReviewForViewedRound: Bool {
        viewedRound?.peerReviews.values.contains { !$0.isEmpty } ?? false
    }
    /// One-round bounded debate: available once peer review exists, and only until it has run once
    /// (hard cap — a single rebuttal round per round, so cost stays bounded).
    public var canRebut: Bool { hasPeerReviewForViewedRound && !hasRebuttalForViewedRound }
    public var hasRebuttalForViewedRound: Bool {
        viewedRound?.rebuttals.values.contains { !$0.isEmpty } ?? false
    }
    /// The revised (or held) answer a seat gave in the rebuttal round, if any.
    public func viewedRebuttal(_ seatID: Int) -> String? {
        guard let r = viewedRound?.rebuttals[seatID], !r.isEmpty else { return nil }
        return r
    }
    public var synthesizerName: String? { synthesizerSeat?.provider?.panelName }
    public var hasSession: Bool { rounds.contains { !$0.answeredSeatIDs.isEmpty } }

    // MARK: - Rounds

    /// Round 1: a NEW round; every connected seat answers in parallel, streaming token-by-token,
    /// each with its own prior context. An optional image rides on the question.
    /// Round 1. An optional `document` is analyzed by EVERY seat alongside the question — the core
    /// "pressure-test this AI output with other models" use case. Like an image, the document rides
    /// on the request only: history + the saved round keep just the typed question, so a big doc
    /// never bloats the sidebar or follow-up context.
    public func ask(_ query: String, image: ImageAttachment? = nil, document: String? = nil) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        // Defend the public API: a whitespace-only document is no document, regardless of caller hygiene.
        let trimmedDoc = document?.trimmingCharacters(in: .whitespacesAndNewlines)
        let doc = (trimmedDoc?.isEmpty == false) ? trimmedDoc : nil
        guard !trimmed.isEmpty || image != nil || doc != nil else { return }
        let question = trimmed.isEmpty
            ? (doc != nil ? "Analyze the attached document." : "Describe and assess this image.")
            : trimmed
        // The document is folded into the prompt every seat receives, but NOT saved as the question.
        let effectivePrompt = doc.map { "\(question)\n\n--- ATTACHED DOCUMENT ---\n\n\($0)" } ?? question

        let keyed = seats.filter { hasKey($0) }
        guard !keyed.isEmpty else { return }
        var round = Round(question: question)
        for seat in keyed { round.answers[seat.id] = "" }   // in-progress slots
        rounds.append(round)
        let idx = rounds.count - 1
        viewingRound = idx
        clearDeliberationErrors()
        generatingRound = idx
        for seat in keyed { status[seat.id] = .loading }

        await withTaskGroup(of: Void.self) { group in
            for seat in keyed {
                let sys = systemPrompt(for: seat)
                // Only hand the image to models that accept it; a text-only model would 400.
                let seatImage = (seat.provider?.supportsVision(model: seat.model) ?? false) ? image : nil
                let messages = [ChatMessage.system(sys)] + (history[seat.id] ?? []) + [.user(effectivePrompt, image: seatImage)]
                group.addTask { @MainActor in
                    let r = await self.streamCall(seat: seat, messages: messages) { partial in
                        self.setAnswer(idx, seat.id, partial)
                    }
                    self.finishAnswer(roundIndex: idx, seat: seat, question: question, result: r)
                }
            }
        }
        generatingRound = nil
        saveConversation()
    }

    /// Round 2: each advisor reviews the others' answers (anonymized) for the VIEWED round.
    public func peerReview() async {
        let idx = viewingRound
        let answered = answeredSeats(in: idx)
        guard answered.count >= 2, rounds.indices.contains(idx) else { return }
        let pairs = answered.map { (seat: $0, answer: rounds[idx].answers[$0.id] ?? "") }
        deliberationBusy = true
        generatingRound = idx
        for s in answered { status[s.id] = .loading; rounds[idx].peerReviews[s.id] = "" }
        // Re-running peer review invalidates the rebuttal round that followed the OLD reviews —
        // clear it so DEBATE unlocks again instead of showing a stale final take.
        rounds[idx].rebuttals.removeAll()

        await withTaskGroup(of: Void.self) { group in
            for (seat, myAnswer) in pairs {
                let others = pairs.filter { $0.seat.id != seat.id }
                // Blind the reviewer with anonymous labels (no brand bias), but keep a map back
                // to real names so the READER sees "I disagree with Gemini", not "Advisor B".
                var remap: [String: String] = [:]
                let othersText = others.enumerated().map { i, p -> String in
                    let label = "Advisor \(String(UnicodeScalar(65 + i)!))"
                    remap[label] = p.seat.provider?.panelName ?? "Advisor"
                    return "\(label) said:\n\(p.answer)"
                }.joined(separator: "\n\n")
                let reviewText = """
                Your own answer was:

                \(myAnswer)

                The other advisors answered the same question as follows:

                \(othersText)

                Review their answers: where do you agree, where do you disagree, and would you refine your own answer? Be specific.
                """
                // The devil's advocate gets an adversarial brief instead of the standard reviewer one.
                let reviewSystem = (seat.id == devilsAdvocateSeatID) ? Self.adversaryReviewPrompt : Self.peerReviewPrompt
                let messages = [ChatMessage.system(reviewSystem), .user(reviewText)]
                group.addTask { @MainActor in
                    let r = await self.streamCall(seat: seat, messages: messages) { partial in
                        if self.rounds.indices.contains(idx) {
                            self.rounds[idx].peerReviews[seat.id] = self.deAnonymize(partial, remap)
                        }
                    }
                    guard self.rounds.indices.contains(idx) else { return }
                    if let text = r.text {
                        self.rounds[idx].peerReviews[seat.id] = self.deAnonymize(text, remap)
                        self.status[seat.id] = .idle
                        self.addRoundUsage(idx, seat, r)
                    } else if r.cancelled {
                        self.status[seat.id] = .idle
                    } else {
                        self.rounds[idx].peerReviews[seat.id] = nil
                        self.status[seat.id] = .failed(r.error ?? "Unknown error")
                    }
                }
            }
        }
        deliberationBusy = false
        generatingRound = nil
        saveConversation()
    }

    /// Bounded debate — one optional rebuttal round. Each advisor sees its own answer plus where the
    /// whole council landed (anonymized, so no brand bias creeps back in) and either revises or holds,
    /// briefly saying why. Hard-capped at a single round per round so cost can't run away.
    public func runRebuttal() async {
        let idx = viewingRound
        let answered = answeredSeats(in: idx)
        guard answered.count >= 2, rounds.indices.contains(idx), !hasRebuttalForViewedRound else { return }
        deliberationBusy = true
        generatingRound = idx
        pipelineStage = "Debate"
        for s in answered { status[s.id] = .loading; rounds[idx].rebuttals[s.id] = "" }
        let pairs = answered.map { (seat: $0, answer: rounds[idx].answers[$0.id] ?? "") }

        await withTaskGroup(of: Void.self) { group in
            for seat in answered {
                let myAnswer = rounds[idx].answers[seat.id] ?? ""
                // Anonymize only the OTHER advisors (like peer review). Including the seat's own
                // answer in the blind set makes it read its own position as a stranger's — and after
                // de-anonymization it ends up "agreeing with itself" by name on screen.
                let others = pairs.filter { $0.seat.id != seat.id }
                var remap: [String: String] = [:]
                let ctx = others.enumerated().map { i, p -> String in
                    let label = "Advisor \(String(UnicodeScalar(65 + i)!))"
                    remap[label] = p.seat.provider?.panelName ?? "Advisor"
                    return "\(label):\n\(p.answer)"
                }.joined(separator: "\n\n")
                let prompt = """
                The council was asked:

                \(rounds[idx].question)

                Your earlier answer:

                \(myAnswer)

                Here is where the other advisors landed (anonymized):

                \(ctx)

                Reconsider in light of the disagreement. If another position exposes a real weakness in \
                yours, revise — and say what changed and why. If you still hold your position, say so and \
                give the strongest reason it survives the critique. Be decisive; this is your final take.
                """
                let messages = [ChatMessage.system(systemPrompt(for: seat)), .user(prompt)]
                group.addTask { @MainActor in
                    let r = await self.streamCall(seat: seat, messages: messages) { partial in
                        if self.rounds.indices.contains(idx) {
                            self.rounds[idx].rebuttals[seat.id] = self.deAnonymize(partial, remap)
                        }
                    }
                    guard self.rounds.indices.contains(idx) else { return }
                    if let text = r.text, !r.cancelled {
                        self.rounds[idx].rebuttals[seat.id] = self.deAnonymize(text, remap)
                        self.status[seat.id] = .idle
                        self.addRoundUsage(idx, seat, r)
                    } else if r.cancelled {
                        self.rounds[idx].rebuttals[seat.id] = nil
                        self.status[seat.id] = .idle
                    } else {
                        self.rounds[idx].rebuttals[seat.id] = nil
                        self.status[seat.id] = .failed(r.error ?? "Unknown error")
                    }
                }
            }
        }
        deliberationBusy = false
        generatingRound = nil
        pipelineStage = nil
        saveConversation()
    }

    /// The single-page flow: once a round's answers are in, the deliberation stages run
    /// automatically in pipeline order. Each stage skips itself if it already exists, so this is
    /// safe to call after a regenerate too. Cancellation (Stop) exits between stages.
    public func runAutoPipeline() async {
        let idx = viewingRound
        guard rounds.indices.contains(idx), answeredSeats(in: idx).count >= 2 else { return }
        if !hasPeerReviewForViewedRound, !Task.isCancelled {
            pipelineStage = "Peer review"
            await peerReview()
        }
        if rounds.indices.contains(idx), rounds[idx].divergence == nil, !Task.isCancelled {
            pipelineStage = "Divergence"
            await runDivergence()
        }
        if rounds.indices.contains(idx), rounds[idx].synthesis == nil, !Task.isCancelled {
            pipelineStage = "Synthesis"
            await runSynthesis()
        }
        pipelineStage = nil
    }

    public func runDivergence() async {
        let idx = viewingRound
        guard canDeliberate(idx), let seat = synthesizerSeat, rounds.indices.contains(idx) else { return }
        deliberationBusy = true
        divergenceError = nil
        // Don't wipe an existing divergence up front: on a failed REGEN the prior good text stays,
        // and the stream replaces it from the first token on success.
        let (ctx, remap, seatByLabel) = anonymizedContext(idx)
        let user = "Question:\n\(rounds[idx].question)\n\nThe advisors' answers (anonymized):\n\n\(ctx)"
        let r = await streamCall(seat: seat, messages: [.system(Self.divergencePrompt), .user(user)]) { partial in
            if self.rounds.indices.contains(idx) { self.rounds[idx].divergence = self.deAnonymize(partial, remap) }
        }
        if rounds.indices.contains(idx) {
            if let t = r.text, !r.cancelled {
                rounds[idx].divergence = deAnonymize(t, remap); addRoundUsage(idx, seat, r)
                await computeVerdict(seat: seat, idx: idx, user: user, remap: remap, seatByLabel: seatByLabel)
            }
            else if !r.cancelled { divergenceError = r.error ?? "Failed" }   // transient, never persisted as content
        }
        deliberationBusy = false
        saveConversation()
    }

    public func runSynthesis() async {
        let idx = viewingRound
        guard canDeliberate(idx), let seat = synthesizerSeat, rounds.indices.contains(idx) else { return }
        deliberationBusy = true
        synthesisError = nil
        let (ctx, remap, _) = anonymizedContext(idx)
        let context = "Question:\n\(rounds[idx].question)\n\nThe advisors' answers (anonymized):\n\n\(ctx)"
        let r = await streamCall(seat: seat, messages: [.system(Self.synthesisPrompt), .user(context)]) { partial in
            if self.rounds.indices.contains(idx) { self.rounds[idx].synthesis = self.deAnonymize(partial, remap) }
        }
        if rounds.indices.contains(idx) {
            if let t = r.text, !r.cancelled { rounds[idx].synthesis = deAnonymize(t, remap); addRoundUsage(idx, seat, r) }
            else if !r.cancelled { synthesisError = r.error ?? "Failed" }   // transient, never persisted as content
        }
        deliberationBusy = false
        saveConversation()
    }

    /// Re-run a single advisor's answer in the latest round (only when viewing it).
    public func regenerate(seatID: Int) async {
        let idx = rounds.count - 1
        guard idx == viewingRound, rounds.indices.contains(idx), !anyLoading,
              let seat = seats.first(where: { $0.id == seatID }), hasKey(seat) else { return }
        let q = rounds[idx].question
        // Only drop this seat's last exchange from history if it actually succeeded (so a
        // retry-after-failure doesn't wrongly delete a previous round's exchange).
        let hadAnswer = !((rounds[idx].answers[seatID] ?? "").isEmpty)
        if hadAnswer, var h = history[seatID], h.count >= 2 { h.removeLast(2); history[seatID] = h }
        // Changing one answer invalidates every peer review (they all read the old set), the rebuttal
        // round, and both cross-model artifacts — clear them all so nothing stale survives next to
        // the new answer (a surviving rebuttal would also lock DEBATE for this round forever).
        rounds[idx].peerReviews.removeAll()
        rounds[idx].rebuttals.removeAll()
        rounds[idx].divergence = nil
        rounds[idx].divergenceScore = nil; rounds[idx].divergenceCamps = nil
        rounds[idx].outlier = nil; rounds[idx].outlierSeatID = nil
        rounds[idx].synthesis = nil
        divergenceError = nil; synthesisError = nil
        rounds[idx].answers[seatID] = ""
        status[seatID] = .loading
        generatingRound = idx
        let messages = [ChatMessage.system(systemPrompt(for: seat))] + (history[seatID] ?? []) + [.user(q)]
        let r = await streamCall(seat: seat, messages: messages) { partial in
            self.setAnswer(idx, seatID, partial)
        }
        finishAnswer(roundIndex: idx, seat: seat, question: q, result: r)
        generatingRound = nil
        saveConversation()
    }

    public func cancelAll() {
        for id in status.keys where status[id] == .loading { status[id] = .idle }
        deliberationBusy = false
        generatingRound = nil
        pipelineStage = nil
    }

    // MARK: - Round helpers

    private func systemPrompt(for seat: Seat) -> String {
        (seat.systemPrompt?.isEmpty == false) ? seat.systemPrompt! : sharedSystemPrompt
    }

    private func setAnswer(_ idx: Int, _ seatID: Int, _ text: String) {
        guard rounds.indices.contains(idx) else { return }
        rounds[idx].answers[seatID] = text
    }

    private func finishAnswer(roundIndex idx: Int, seat: Seat, question: String, result r: StreamResult) {
        guard rounds.indices.contains(idx) else { return }
        let id = seat.id
        if let text = r.text, !r.cancelled {
            // Completed normally → commit the answer and extend this seat's conversation history.
            rounds[idx].answers[id] = text
            rounds[idx].answerProviders[id] = seat.provider?.panelName
            history[id, default: []].append(.user(question))
            history[id, default: []].append(.assistant(text))
            status[id] = .idle
            addRoundUsage(idx, seat, r)
        } else if r.cancelled {
            // Stopped mid-stream: keep whatever streamed for the user to read, but do NOT append it
            // to history — feeding a truncated answer into later rounds as if complete corrupts context.
            rounds[idx].answers[id] = r.text   // partial text, or nil if nothing arrived yet
            rounds[idx].answerProviders[id] = seat.provider?.panelName
            status[id] = .idle
        } else {
            rounds[idx].answers[id] = nil   // hard failure → drop the empty in-progress slot
            status[id] = .failed(r.error ?? "Unknown error")
        }
    }

    /// Optional price override (the CouncilKit facade) so a stale built-in price can't silently
    /// mislead. Keyed on (provider, model) because models within one provider price differently.
    /// Returns ($/1M input, $/1M output); nil → the provider's built-in price. Non-persisted.
    public var priceOverride: (@Sendable (LLMProvider, String?) -> (inputPer1M: Double, outputPer1M: Double)?)?

    private func addRoundUsage(_ idx: Int, _ seat: Seat, _ r: StreamResult) {
        guard rounds.indices.contains(idx), let provider = seat.provider,
              r.input > 0 || r.output > 0 else { return }
        rounds[idx].inputTokens += r.input
        rounds[idx].outputTokens += r.output
        let rates = priceOverride?(provider, seat.model.isEmpty ? nil : seat.model)
            ?? (inputPer1M: provider.pricePer1MInput, outputPer1M: provider.pricePer1MOutput)
        rounds[idx].costUSD += Double(r.input) / 1_000_000 * rates.inputPer1M
                             + Double(r.output) / 1_000_000 * rates.outputPer1M
    }

    /// Build the answers for the synthesizer with ANONYMOUS, shuffled labels (Advisor A/B/C) so it
    /// can't tell which answer is its own and favor it. Returns the context plus a map from each
    /// anonymous label back to the real provider name (used to restore attribution in the output).
    private func anonymizedContext(_ idx: Int) -> (context: String, remap: [String: String], seatByLabel: [String: Int]) {
        let answered = answeredSeats(in: idx).shuffled()
        var blocks: [String] = []
        var remap: [String: String] = [:]
        var seatByLabel: [String: Int] = [:]   // lowercased label → seat id (verdict outlier resolution)
        for (i, s) in answered.enumerated() {
            let label = "Advisor \(String(UnicodeScalar(65 + i)!))"   // Advisor A, B, C…
            remap[label] = s.provider?.panelName ?? "Advisor"
            seatByLabel[label.lowercased()] = s.id
            blocks.append("\(label):\n\(rounds[idx].answers[s.id] ?? "")")
        }
        return (blocks.joined(separator: "\n\n"), remap, seatByLabel)
    }

    /// Put the real provider names back into a generated artifact, for display.
    private func deAnonymize(_ text: String, _ remap: [String: String]) -> String {
        var out = text
        for (label, name) in remap { out = out.replacingOccurrences(of: label, with: name) }
        return out
    }

    /// Separate, json-mode "verdict" call on the synthesizer: a reliable agreement score, camp count,
    /// and outlier — instead of a free-form line a small model might drop. Free for local synthesizers.
    private func computeVerdict(seat: Seat, idx: Int, user: String,
                                remap: [String: String], seatByLabel: [String: Int]) async {
        guard let provider = seat.provider else { return }
        var key = ""
        if let k = transientKeys[seat.id], !k.isEmpty {
            key = k                                          // facade-supplied key (also auths custom endpoints)
        } else if provider.requiresAPIKey {
            guard let k = storedKey(for: provider) else { return }
            key = k
        }
        let client = LLMClientFactory.make(for: provider, model: seat.model,
                                           endpoint: transientCustomEndpoints[seat.id])
        // Parse the RAW output — the outlier is still an anonymous label ("Advisor B"), which we
        // resolve to a seat id HERE (case-insensitively). Matching by display name later is fragile:
        // duplicate providers share a panel name, and judges drift on label casing.
        guard let raw = try? await client.judge(messages: [.system(Self.verdictPrompt), .user(user)], apiKey: key),
              let v = Self.parseVerdictJSON(raw) else { return }
        if rounds.indices.contains(idx) {
            rounds[idx].divergenceScore = v.agreement
            rounds[idx].divergenceCamps = v.camps
            if let label = v.outlier {
                let k = label.lowercased().trimmingCharacters(in: .whitespaces)
                rounds[idx].outlierSeatID = seatByLabel[k]
                rounds[idx].outlier = remap[label]
                    ?? remap.first { $0.key.lowercased() == k }?.value
                    ?? label
            } else {
                rounds[idx].outlierSeatID = nil
                rounds[idx].outlier = nil
            }
        }
    }

    /// Robust parse of the judge's JSON — tolerant of the schema drift small models produce (camps as
    /// an array → use its count, agreement as a string, "none"/null outliers).
    private static func parseVerdictJSON(_ text: String) -> (agreement: Int, camps: Int?, outlier: String?)? {
        guard let s = text.firstIndex(of: "{"), let e = text.lastIndex(of: "}"), s < e,
              let data = String(text[s...e]).data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        func intify(_ v: Any?) -> Int? {
            if let i = v as? Int { return i }
            if let d = v as? Double { return Int(d) }
            if let str = v as? String { return Int(str.filter(\.isNumber)) }
            if let arr = v as? [Any] { return arr.count }
            return nil
        }
        guard let a = intify(obj["agreement"]) else { return nil }
        let camps = intify(obj["camps"])
        var outlier: String? = nil
        if let o = obj["outlier"] as? String, !o.isEmpty,
           o.lowercased() != "none", o.lowercased() != "null" { outlier = o }
        return (min(100, max(0, a)), camps, outlier)
    }

    public typealias StreamResult = (text: String?, input: Int, output: Int, cancelled: Bool, error: String?)

    /// Stream one model call, feeding the growing text to `onDelta`. Returns final text (nil on
    /// hard failure), token usage, and whether it was cancelled (partial text is kept on cancel).
    private func streamCall(seat: Seat, messages: [ChatMessage],
                            onDelta: @MainActor @escaping (String) -> Void) async -> StreamResult {
        guard let provider = seat.provider else { return (nil, 0, 0, false, "No model selected.") }
        var apiKey = ""
        if let k = transientKeys[seat.id], !k.isEmpty {
            apiKey = k                                       // facade-supplied key (also auths custom endpoints)
        } else if provider.requiresAPIKey {
            guard let key = (try? KeychainStore.read(account: provider.keychainAccount)) ?? nil,
                  !key.isEmpty else { return (nil, 0, 0, false, "API key not found.") }
            apiKey = key
        }
        let client = LLMClientFactory.make(for: provider, model: seat.model,
                                           temperature: seat.temperature, maxTokens: seat.maxTokens,
                                           endpoint: transientCustomEndpoints[seat.id])
        // Coalesce token updates to ~30fps. Streaming fires hundreds of deltas/answer; pushing
        // every one into the UI re-renders + re-parses markdown each time (O(n²)). We only flush
        // to the UI every ~33ms, and always flush the final text after the loop.
        let minInterval: UInt64 = 33_000_000   // 33ms in ns

        // One automatic retry on a transient connection drop (flaky Wi-Fi, an SSH-tunnelled remote
        // Ollama, a brief blip). The long streaming connection is what tends to fail, so we re-run
        // from scratch once before surfacing the error — the seat stays in its loading state throughout.
        var lastError: Error = LLMError.message("Failed")
        for attempt in 0..<2 {
            var full = "", input = 0, output = 0
            var lastEmit: UInt64 = 0
            var pending = false
            do {
                for try await chunk in client.stream(messages: messages, apiKey: apiKey) {
                    try Task.checkCancellation()   // Stop → exit → stream terminates → network cancels
                    switch chunk {
                    case .text(let t):
                        full += t
                        let now = DispatchTime.now().uptimeNanoseconds
                        if now &- lastEmit >= minInterval { lastEmit = now; pending = false; onDelta(full) }
                        else { pending = true }
                    case .usage(let i, let o): input = i; output = o
                    }
                }
                if pending { onDelta(full) }   // flush the last buffered text
                return (full, input, output, false, nil)
            } catch {
                if pending { onDelta(full) }   // flush whatever streamed before the error/cancel
                if error is CancellationError || (error as? URLError)?.code == .cancelled {
                    return (full.isEmpty ? nil : full, input, output, true, nil)
                }
                lastError = error
                if attempt == 0, !Task.isCancelled, Self.isTransient(error) {
                    try? await Task.sleep(nanoseconds: 500_000_000)   // brief backoff, then re-run once
                    continue
                }
                return (nil, input, output, false, Self.friendlyError(error, provider: provider))
            }
        }
        return (nil, 0, 0, false, Self.friendlyError(lastError, provider: provider))
    }

    /// A transient connection failure worth one automatic retry (vs a permanent auth/model error,
    /// which a retry wouldn't fix).
    private static func isTransient(_ error: Error) -> Bool {
        guard let u = error as? URLError else { return false }
        switch u.code {
        case .networkConnectionLost, .timedOut, .cannotConnectToHost, .cannotFindHost,
             .notConnectedToInternet, .cannotLoadFromNetwork, .dnsLookupFailed, .secureConnectionFailed:
            return true
        default: return false
        }
    }

    /// Turn a raw networking error into a clear, provider-aware message. The common confusing case
    /// is a local Ollama that simply isn't running — say so plainly instead of "Could not connect…".
    private static func friendlyError(_ error: Error, provider: LLMProvider) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .cannotConnectToHost, .cannotFindHost, .networkConnectionLost,
                 .notConnectedToInternet, .timedOut, .cannotLoadFromNetwork, .dnsLookupFailed:
                if provider == .ollama {
                    return "Can't reach Ollama at \(LLMProvider.ollamaHost) — is it running? Start it with 'ollama serve', or set a different address in Settings → Models."
                }
                if let slot = provider.customSlot {
                    return "Can't reach \(provider.panelName) at \(LLMProvider.customHost(slot)) — is the server running and reachable from this Mac?"
                }
                return "Couldn't reach \(provider.panelName). Check your connection and try again."
            default:
                break
            }
        }
        return error.localizedDescription
    }

    // MARK: - Export

    public func exportMarkdown() -> String {
        // Attribute by what's RECORDED on the round, not the current seat assignment — a reopened
        // session may have different (or no) providers on its seats today.
        func name(_ round: Round, _ seatID: Int) -> String {
            round.answerProviders[seatID] ?? seats.first { $0.id == seatID }?.provider?.panelName ?? "Advisor"
        }
        var out = "# Council\n\n"
        for (i, round) in rounds.enumerated() where !round.answeredSeatIDs.isEmpty {
            out += "## Round \(i + 1) — \(round.question)\n\n"
            for seat in seats where !((round.answers[seat.id] ?? "").isEmpty) {
                // Only attach the model id when this seat's current provider is the one that answered.
                let model = (seat.provider?.panelName == round.answerProviders[seat.id]) ? " — `\(seat.model)`" : ""
                out += "### \(name(round, seat.id))\(model)\n\n\(round.answers[seat.id] ?? "")\n\n"
            }
            let reviews = seats.filter { !((round.peerReviews[$0.id] ?? "").isEmpty) }
            if !reviews.isEmpty {
                out += "#### Peer Review\n\n"
                for seat in reviews { out += "**\(name(round, seat.id)):** \(round.peerReviews[seat.id] ?? "")\n\n" }
            }
            let rebuts = seats.filter { !((round.rebuttals[$0.id] ?? "").isEmpty) }
            if !rebuts.isEmpty {
                out += "#### Debate — final takes\n\n"
                for seat in rebuts { out += "**\(name(round, seat.id)):** \(round.rebuttals[seat.id] ?? "")\n\n" }
            }
            if let d = round.divergence { out += "#### Divergence\n\n\(d)\n\n" }
            if let s = round.synthesis { out += "#### Synthesis\n\n\(s)\n\n" }
        }
        if let cur = sessions.first(where: { $0.id == currentSessionID }),
           let d = cur.decision, !d.isEmpty {
            out += "## Decision\n\n\(d)\n\n"
            if let o = cur.outcome, !o.isEmpty { out += "**How it turned out:** \(o)\n\n" }
        }
        return out
    }

    /// A decision-ready Markdown memo for the VIEWED round — readable enough to paste into a
    /// design doc or ADR as-is. Excerpts (not full transcripts) for answers; full synthesis.
    /// No keys, no internal ids.
    public func exportDecisionMemo() -> String {
        guard rounds.indices.contains(viewingRound) else { return "" }
        let round = rounds[viewingRound]

        /// First markdown paragraph of a text, capped — a deterministic, zero-cost "summary".
        func excerpt(_ text: String, cap: Int = 500) -> String {
            let para = text
                .components(separatedBy: "\n\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first { !$0.isEmpty && !$0.hasPrefix("#") } ?? text
            let flat = para.replacingOccurrences(of: "\n", with: " ")
            return flat.count <= cap ? flat : String(flat.prefix(cap)).trimmingCharacters(in: .whitespaces) + "…"
        }
        func name(_ seatID: Int) -> String {
            round.answerProviders[seatID] ?? seats.first { $0.id == seatID }?.provider?.panelName ?? "Advisor"
        }

        let df = ISO8601DateFormatter(); df.formatOptions = [.withFullDate]
        var out = "# Council decision memo\n\n"
        out += "*\(df.string(from: Date()))*\n\n"
        out += "## Question\n\n\(round.question)\n\n"

        out += "## Council\n\n"
        for seat in seats where round.answers[seat.id]?.isEmpty == false {
            let model = (seat.provider?.panelName == round.answerProviders[seat.id]) ? " — `\(seat.model)`" : ""
            out += "- \(name(seat.id))\(model)\n"
        }
        out += "\n## Answers (excerpts)\n\n"
        for seat in seats {
            if let a = round.answers[seat.id], !a.isEmpty {
                out += "**\(name(seat.id)):** \(excerpt(a))\n\n"
            }
        }

        if let agreement = round.divergenceScore {
            out += "## Divergence\n\n"
            out += "- **Divergence: \(100 - agreement)/100** (how far apart the council landed)\n"
            if let c = round.divergenceCamps { out += "- Camps: \(c)\n" }
            if let o = round.outlier { out += "- Outlier: \(o)\n" }
            out += "\n*Measures agreement, not correctness — models can share the same blind spot.*\n\n"
        }
        if let outlier = round.outlier {
            let dissentAnswer = round.outlierSeatID.flatMap { round.answers[$0] }
                ?? round.answerProviders.first { $0.value == outlier }.flatMap { round.answers[$0.key] }
            if let d = dissentAnswer, !d.isEmpty {
                out += "## Minority view — \(outlier)\n\n\(excerpt(d, cap: 700))\n\n"
            }
        }
        if let s = round.synthesis, !s.isEmpty {
            out += "## Synthesis\n\n\(s)\n\n"
        }
        if let cur = sessions.first(where: { $0.id == currentSessionID }),
           let d = cur.decision, !d.isEmpty {
            out += "## Decision\n\n\(d)\n\n"
            if let o = cur.outcome, !o.isEmpty { out += "**Outcome:** \(o)\n\n" }
        }
        return out
    }

    // MARK: - Sessions (local multi-session history — one JSON file each, no server)

    public var sessions: [Session] = []
    private var currentSessionID = UUID()
    private var currentTitle = ""
    private var currentCreatedAt = Date()
    public var currentSession: UUID { currentSessionID }

    public static var sessionsFolderURL: URL? {
        let fm = FileManager.default
        // Inside the sandboxed app, application-support already resolves into the app container.
        // A NON-sandboxed process (the `council` CLI) must target that container explicitly, so
        // CLI runs land in the same history the app shows.
        if ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] == nil {
            let container = fm.homeDirectoryForCurrentUser.appendingPathComponent(
                "Library/Containers/com.joseph.Council/Data/Library/Application Support/Council/Sessions")
            if fm.fileExists(atPath: container.path) { return container }
        }
        guard let base = try? fm.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        ) else { return nil }
        let dir = base.appendingPathComponent("Council/Sessions", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    public var conversationFolderDisplayPath: String {
        guard let dir = Self.sessionsFolderURL else { return "—" }
        return dir.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }
    public var conversationFileDisplayPath: String { conversationFolderDisplayPath }

    private func sessionURL(_ id: UUID) -> URL? {
        Self.sessionsFolderURL?.appendingPathComponent("\(id.uuidString).json")
    }
    private static var sessionCoder: (enc: JSONEncoder, dec: JSONDecoder) {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        return (e, d)
    }

    public func loadSessions() {
        guard let dir = Self.sessionsFolderURL,
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        let dec = Self.sessionCoder.dec
        var loaded: [Session] = []
        for f in files where f.pathExtension == "json" {
            if let data = try? Data(contentsOf: f), let s = try? dec.decode(Session.self, from: data) { loaded.append(s) }
        }
        sessions = loaded.sorted { $0.updatedAt > $1.updatedAt }
        if let recent = sessions.first { apply(recent) }
    }

    private var derivedTitle: String {
        let q = (rounds.first?.question ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return q.isEmpty ? "Untitled" : String(q.prefix(48))
    }

    public func saveConversation() {
        guard persistenceEnabled, hasSession else { return }
        if currentTitle.isEmpty { currentTitle = derivedTitle }
        let prior = sessions.first { $0.id == currentSessionID }
        var s = Session(id: currentSessionID, title: currentTitle,
                        createdAt: currentCreatedAt, updatedAt: Date(),
                        rounds: rounds, history: history)
        // Carry the decision-journal fields forward — they live out-of-band from the live round state,
        // so a plain rebuild would silently wipe them on the next save.
        s.decision = prior?.decision; s.decisionAt = prior?.decisionAt
        s.outcome = prior?.outcome; s.outcomeAt = prior?.outcomeAt
        if let url = sessionURL(s.id), let data = try? Self.sessionCoder.enc.encode(s) {
            try? data.write(to: url, options: .atomic)
        }
        sessions.removeAll { $0.id == s.id }
        sessions.insert(s, at: 0)
        haystackCache[s.id] = nil   // its transcript changed → rebuild on next search
        checkSpendAlert()
    }

    // MARK: - Decision journal (local only)

    /// Sessions that have a recorded decision, newest decision first — the journal feed.
    public var journal: [Session] {
        sessions.filter { ($0.decision?.isEmpty == false) }
                .sorted { ($0.decisionAt ?? .distantPast) > ($1.decisionAt ?? .distantPast) }
    }
    /// Record (or update) what the user actually decided after this council.
    public func recordDecision(_ text: String, for id: UUID) {
        if id == currentSessionID && !sessions.contains(where: { $0.id == id }) { saveConversation() }
        updateSession(id) { $0.decision = text; $0.decisionAt = Date() }
    }
    /// Record how a past decision turned out — closing the loop on whether the council's read held up.
    public func recordOutcome(_ text: String, for id: UUID) {
        updateSession(id) { $0.outcome = text; $0.outcomeAt = Date() }
    }
    private func updateSession(_ id: UUID, _ mutate: (inout Session) -> Void) {
        guard let i = sessions.firstIndex(where: { $0.id == id }) else { return }
        mutate(&sessions[i])
        haystackCache[id] = nil   // the journal text is searchable → rebuild on next search
        if let url = sessionURL(id), let data = try? Self.sessionCoder.enc.encode(sessions[i]) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private func apply(_ s: Session) {
        currentSessionID = s.id
        currentTitle = s.title
        currentCreatedAt = s.createdAt
        rounds = s.rounds
        history = s.history
        viewingRound = max(0, rounds.count - 1)
        status = [:]
        clearDeliberationErrors()
    }

    public func openSession(_ s: Session) {
        guard !anyLoading else { return }   // don't swap rounds out from under a running task
        apply(s)
    }

    public func newSession() {
        guard !anyLoading else { return }
        currentSessionID = UUID()
        currentTitle = ""
        currentCreatedAt = Date()
        rounds = []
        viewingRound = 0
        status = [:]
        history = [:]
        clearDeliberationErrors()
    }

    public func renameSession(_ id: UUID, to title: String) {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        if id == currentSessionID { currentTitle = t }
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[idx].title = t
        if let url = sessionURL(id), let data = try? Self.sessionCoder.enc.encode(sessions[idx]) {
            try? data.write(to: url, options: .atomic)
        }
    }

    public func deleteSession(_ id: UUID) {
        // Deleting the active session resets rounds → must not happen mid-generation.
        if id == currentSessionID && anyLoading { return }
        if let url = sessionURL(id) { try? FileManager.default.removeItem(at: url) }
        sessions.removeAll { $0.id == id }
        if id == currentSessionID { newSession() }
    }

    /// Lowercased search text per session, built once and reused so typing in the history search
    /// doesn't rebuild every transcript on every keystroke. Invalidated when a session is saved.
    private var haystackCache: [UUID: String] = [:]
    private func haystack(_ s: Session) -> String {
        if let cached = haystackCache[s.id] { return cached }
        let h = s.searchHaystack
        haystackCache[s.id] = h
        return h
    }

    public func searchedSessions(_ query: String) -> [Session] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return q.isEmpty ? sessions : sessions.filter { haystack($0).contains(q) }
    }

    public func revealConversationFolder() {
        guard let dir = Self.sessionsFolderURL else { return }
        NSWorkspace.shared.open(dir)
    }
}
