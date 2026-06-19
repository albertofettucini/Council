import Foundation

/// An image attached to a question. Re-encoded to PNG before it reaches here.
/// `Sendable` so it can cross into the parallel task group. The image rides only on the
/// transient request; only the text question is appended to saved history, so session
/// files on disk never carry image bytes.
public struct ImageAttachment: Sendable, Codable {
    public let data: Data
    public let mediaType: String           // e.g. "image/png"
    public var base64: String { data.base64EncodedString() }
    public init(data: Data, mediaType: String) { self.data = data; self.mediaType = mediaType }
}

/// One message in a conversation. `system` carries instructions; `user`/`assistant`
/// carry the back-and-forth. An image may ride on a user message. This is the unit the
/// whole deliberation pipeline is built on — multi-turn history, and (soon) feeding each
/// model the others' answers for peer review.
public struct ChatMessage: Sendable, Codable {
    public enum Role: String, Sendable, Codable { case system, user, assistant }
    public let role: Role
    public let text: String
    public var image: ImageAttachment? = nil

    public static func system(_ t: String) -> ChatMessage { .init(role: .system, text: t) }
    public static func user(_ t: String, image: ImageAttachment? = nil) -> ChatMessage { .init(role: .user, text: t, image: image) }
    public static func assistant(_ t: String) -> ChatMessage { .init(role: .assistant, text: t) }
}

/// A streamed piece of a response: a text delta, or the final token usage.
public enum StreamChunk: Sendable {
    case text(String)
    case usage(input: Int, output: Int)
}

/// A uniform interface over every LLM backend. Each provider has its own wire format
/// under the hood, but callers only ever see these methods.
public protocol LLMClient {
    /// Token-by-token stream. Yields text deltas as they arrive, then a usage chunk.
    func stream(messages: [ChatMessage], apiKey: String) -> AsyncThrowingStream<StreamChunk, Error>
    /// Cheap key check: makes a tiny authenticated call. Returns normally if the key
    /// works, throws a clear `LLMError` if it's invalid / out of balance / unusable.
    func validate(apiKey: String) async throws
    /// One-shot completion for the structured "divergence verdict". OpenAI-compatible clients override
    /// this to force JSON mode (reliable even on small local models); the default just collects the
    /// normal stream (capable models follow a JSON instruction fine).
    func judge(messages: [ChatMessage], apiKey: String) async throws -> String
}

extension LLMClient {
    public func judge(messages: [ChatMessage], apiKey: String) async throws -> String {
        var full = ""
        for try await chunk in stream(messages: messages, apiKey: apiKey) {
            if case .text(let t) = chunk { full += t }
        }
        return full
    }
}

/// Turns the HTTP status + body of a tiny test call into a clear, user-facing key error.
public enum KeyValidation {
    public static func interpret(status: Int, body: Data) throws {
        if (200..<300).contains(status) { return }
        let text = (String(data: body, encoding: .utf8) ?? "").lowercased()
        switch status {
        case 401, 403:
            // The ONLY real "bad key" signal: the server rejected authentication.
            throw LLMError.message("API key was rejected (unauthorized). Check you pasted the whole key and that it's for this provider.")
        case 402:
            throw LLMError.message("This key has no available balance — add credit / enable billing.")
        case 429:
            // Authenticated fine — a rate/quota limit, not a bad key. Only fail if it's truly out of funds.
            if text.contains("insufficient") || text.contains("exceeded your current quota") {
                throw LLMError.message("This key is out of quota or balance.")
            }
            return
        default:
            // 400 / 404 etc. mean the request got PAST auth (to model resolution), so the key itself
            // is valid — the usual cause is the default model not being enabled for this key/project.
            // Don't mislabel a working key as invalid; the real model error surfaces on the first ask.
            return
        }
    }
}

/// Human-readable error surfaced to the UI.
public enum LLMError: LocalizedError {
    case message(String)
    public var errorDescription: String? {
        switch self { case .message(let text): return text }
    }
}

/// Turns an HTTP error status + response body into a clear, user-facing message — surfaces the
/// provider's own text ("model 'X' does not exist", "invalid api key", "rate limit", …) instead
/// of a bare "HTTP 404", so a wrong model id or key is self-explanatory.
public enum HTTPError {
    public static func describe(_ status: Int, _ body: String) -> String {
        if let data = body.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let e = obj["error"] as? [String: Any], let m = e["message"] as? String { return m }
            if let m = obj["error"] as? String { return m }
            if let m = obj["message"] as? String { return m }
        }
        let t = body.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "HTTP \(status)" : "HTTP \(status): \(t.prefix(160))"
    }
}

/// Picks the right client for a provider. Claude has its own wire format; everything else
/// (GPT, Gemini, DeepSeek, Grok, Mistral, Perplexity, OpenRouter, local Ollama) speaks the
/// OpenAI `/chat/completions` format and shares one client, differing only by endpoint.
public enum LLMClientFactory {
    public static func make(for provider: LLMProvider, model: String,
                     temperature: Double? = nil, maxTokens: Int? = nil,
                     endpoint: URL? = nil) -> LLMClient {
        // Fall back to the provider default if a blank model id ever slips through.
        let model = model.isEmpty ? provider.defaultModel : model
        if provider == .claude {
            return AnthropicClient(model: model, temperature: temperature, maxTokens: maxTokens)
        }
        // A transient (CouncilKit facade) endpoint overrides the provider's configured one — e.g. a
        // custom slot whose UserDefaults URL is unset because the consumer supplied it in code instead.
        let resolved = endpoint ?? provider.openAIEndpoint
        if provider.customSlot != nil, resolved == nil {
            return UnavailableClient(reason: "\(provider.panelName) has no endpoint set — add its server URL in Settings → Models, or pass Advisor(endpoint:).")
        }
        if let resolved {
            return OpenAICompatibleClient(endpoint: resolved, model: model,
                                          temperature: temperature, maxTokens: maxTokens)
        }
        if provider == .foundationModels {
            return AppleFoundationClient(temperature: temperature, maxTokens: maxTokens)
        }
        return UnavailableClient(reason: "\(provider.displayName) isn't available yet.")
    }
}

/// Placeholder for backends we haven't wired yet (e.g. on-device Foundation Models).
public struct UnavailableClient: LLMClient {
    public let reason: String
    public func stream(messages: [ChatMessage], apiKey: String) -> AsyncThrowingStream<StreamChunk, Error> {
        AsyncThrowingStream { $0.finish(throwing: LLMError.message(reason)) }
    }
    public func validate(apiKey: String) async throws {
        throw LLMError.message(reason)
    }
}
