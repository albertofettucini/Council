import Foundation

/// The LLM backends a council seat can use. Most speak the OpenAI `/chat/completions`
/// wire format, so they share `OpenAICompatibleClient`; Claude has its own; Ollama runs
/// locally with no key; Foundation Models is on-device and not wired yet.
public enum LLMProvider: String, CaseIterable, Identifiable, Codable {
    case claude
    case openAI
    case gemini
    case deepSeek
    case grok
    case mistral
    case perplexity
    case openRouter
    case ollama
    case foundationModels
    /// User-defined OpenAI-compatible servers (llama.cpp, LM Studio, vLLM, a second Ollama box…).
    /// Two slots; each appears in the seat picker only once its URL is set in Settings → Models.
    case custom1
    case custom2

    public var id: String { rawValue }

    /// Which custom slot this is (1/2), or nil for built-in providers.
    public var customSlot: Int? { self == .custom1 ? 1 : (self == .custom2 ? 2 : nil) }

    /// Providers offered in the seat picker. Custom slots join only when configured.
    public static var selectable: [LLMProvider] {
        var list: [LLMProvider] = [.claude, .openAI, .gemini, .deepSeek, .grok, .mistral, .perplexity, .openRouter, .ollama]
        if !customHost(1).isEmpty { list.append(.custom1) }
        if !customHost(2).isEmpty { list.append(.custom2) }
        list.append(.foundationModels)
        return list
    }

    public var displayName: String {
        switch self {
        case .claude:           return "Claude"
        case .openAI:           return "GPT (OpenAI)"
        case .gemini:           return "Gemini"
        case .deepSeek:         return "DeepSeek"
        case .grok:             return "Grok (xAI)"
        case .mistral:          return "Mistral"
        case .perplexity:       return "Perplexity"
        case .openRouter:       return "OpenRouter"
        case .ollama:           return "Ollama (local)"
        case .foundationModels: return "Apple (on-device)"
        case .custom1:          return Self.customName(1)
        case .custom2:          return Self.customName(2)
        }
    }

    /// Short label shown on the terminal panels.
    public var panelName: String {
        switch self {
        case .claude:           return "Claude"
        case .openAI:           return "GPT"
        case .gemini:           return "Gemini"
        case .deepSeek:         return "DeepSeek"
        case .grok:             return "Grok"
        case .mistral:          return "Mistral"
        case .perplexity:       return "Perplexity"
        case .openRouter:       return "OpenRouter"
        case .ollama:           return "Ollama"
        case .foundationModels: return "Apple"
        case .custom1:          return Self.customName(1)
        case .custom2:          return Self.customName(2)
        }
    }

    /// A one-line note shown next to the name in the picker (nil = nothing extra).
    public var pickerNote: String? {
        switch self {
        case .ollama:     return "local · no key"
        case .foundationModels: return "on-device · free · no key"
        case .openRouter: return "one key · many models"
        case .perplexity: return "web-grounded"
        case .deepSeek:   return "cheap · reasoning"
        case .custom1, .custom2: return "your server · openai-compatible"
        default:          return nil
        }
    }

    /// Local / on-device / self-hosted backends need no API key. Cloud providers do.
    public var requiresAPIKey: Bool {
        switch self {
        case .ollama, .foundationModels, .custom1, .custom2: return false
        default: return true
        }
    }

    /// Whether this provider's models accept image input. Used to avoid sending an image to a
    /// text-only model (which would hard-fail with HTTP 400). For a given seat we also check the
    /// model id, since within a provider only some models are multimodal.
    public func supportsVision(model: String) -> Bool {
        let m = model.lowercased()
        switch self {
        case .claude, .openAI, .gemini:
            return true   // current flagship Claude / GPT / Gemini families are multimodal
        case .openRouter:
            // OpenRouter routes to many models — assume vision only for known multimodal families.
            return m.contains("gpt") || m.contains("claude") || m.contains("gemini") || m.contains("llama-4") || m.contains("vision")
        case .grok:
            return m.contains("vision") || m.contains("grok-4")
        case .ollama:
            return m.contains("llava") || m.contains("vision") || m.contains("gemma3") || m.contains("llama3.2-vision")
        case .deepSeek, .mistral, .perplexity, .foundationModels, .custom1, .custom2:
            return false  // text-only in practice (custom servers: assume text-only to avoid a hard 400)
        }
    }

    /// Stable identifier used as the Keychain account name for this provider's key.
    public var keychainAccount: String { "apikey.\(rawValue)" }

    /// The provider's official API-key console — shown as a "where do I get a key?" link in the
    /// key-entry step. nil for local/on-device backends that need no key.
    public var consoleURL: URL? {
        switch self {
        case .claude:     return URL(string: "https://console.anthropic.com/settings/keys")
        case .openAI:     return URL(string: "https://platform.openai.com/api-keys")
        case .gemini:     return URL(string: "https://aistudio.google.com/apikey")
        case .deepSeek:   return URL(string: "https://platform.deepseek.com/api_keys")
        case .grok:       return URL(string: "https://console.x.ai")
        case .mistral:    return URL(string: "https://console.mistral.ai/api-keys")
        case .perplexity: return URL(string: "https://www.perplexity.ai/settings/api")
        case .openRouter: return URL(string: "https://openrouter.ai/keys")
        case .ollama, .foundationModels, .custom1, .custom2: return nil
        }
    }

    /// Base URL for local Ollama. Defaults to localhost; the user can point it at Ollama running on
    /// another machine on their network (e.g. a GPU box) via Settings. Plain text (non-secret).
    public static let ollamaHostKey = "council.ollamaHost"
    /// Reads a settings string. In the app this is plain UserDefaults; in the (non-sandboxed) CLI
    /// it falls back to the app's container preferences so endpoints configured in the app just work.
    private static func settingsString(_ key: String) -> String? {
        if let v = UserDefaults.standard.string(forKey: key) { return v }
        guard ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] == nil else { return nil }
        return containerPrefs?[key] as? String
    }
    private static let containerPrefs: NSDictionary? = NSDictionary(contentsOf:
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
            "Library/Containers/com.joseph.Council/Data/Library/Preferences/com.joseph.Council.plist"))
    public static var ollamaHost: String {
        let raw = (settingsString(ollamaHostKey) ?? "").trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else { return "http://localhost:11434" }
        return normalizeHost(raw)
    }

    /// Custom OpenAI-compatible slots (Settings → Models). Host "" = slot unconfigured.
    /// Stored in UserDefaults (a server address, not a secret).
    public static func customHostKey(_ slot: Int) -> String { "council.custom\(slot).host" }
    public static func customNameKey(_ slot: Int) -> String { "council.custom\(slot).name" }
    public static func customHost(_ slot: Int) -> String {
        let raw = (settingsString(customHostKey(slot)) ?? "").trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else { return "" }
        return normalizeHost(raw)
    }
    public static func customName(_ slot: Int) -> String {
        let n = (settingsString(customNameKey(slot)) ?? "").trimmingCharacters(in: .whitespaces)
        return n.isEmpty ? "Custom \(slot)" : n
    }

    /// Scheme-prefix + trailing-slash + trailing-/v1 normalization, shared by Ollama and the custom
    /// slots — people paste base URLs in every shape ("host:8080/", "http://host/v1", …).
    private static func normalizeHost(_ raw: String) -> String {
        var h = (raw.hasPrefix("http://") || raw.hasPrefix("https://")) ? raw : "http://\(raw)"
        while h.hasSuffix("/") { h.removeLast() }
        if h.lowercased().hasSuffix("/v1") { h.removeLast(3); while h.hasSuffix("/") { h.removeLast() } }
        return h
    }

    /// Build an OpenAI-compatible `/chat/completions` URL from a raw base URL, using the same
    /// normalization as the custom slots. Used by the CouncilKit facade for transient (no-disk) endpoints.
    public static func chatEndpoint(forHost raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: "\(normalizeHost(trimmed))/v1/chat/completions")
    }

    /// OpenAI-compatible `/chat/completions` endpoint. nil for backends that don't use the
    /// generic client (Claude has its own; Foundation Models isn't networked).
    public var openAIEndpoint: URL? {
        switch self {
        case .openAI:     return URL(string: "https://api.openai.com/v1/chat/completions")
        case .gemini:     return URL(string: "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions")
        case .deepSeek:   return URL(string: "https://api.deepseek.com/v1/chat/completions")
        case .grok:       return URL(string: "https://api.x.ai/v1/chat/completions")
        case .mistral:    return URL(string: "https://api.mistral.ai/v1/chat/completions")
        case .perplexity: return URL(string: "https://api.perplexity.ai/chat/completions")
        case .openRouter: return URL(string: "https://openrouter.ai/api/v1/chat/completions")
        case .ollama:     return URL(string: "\(Self.ollamaHost)/v1/chat/completions")
        case .custom1:
            let h = Self.customHost(1); return h.isEmpty ? nil : URL(string: "\(h)/v1/chat/completions")
        case .custom2:
            let h = Self.customHost(2); return h.isEmpty ? nil : URL(string: "\(h)/v1/chat/completions")
        case .claude, .foundationModels: return nil
        }
    }

    /// GET endpoint that lists this provider's available models, so the picker can offer what the
    /// user can actually use instead of a fixed suggestion list. Ollama uses /api/tags; OpenRouter's
    /// /models is public; everything else is the chat base with `/models` (queried with the key).
    public var modelsEndpoint: URL? {
        switch self {
        case .claude:           return URL(string: "https://api.anthropic.com/v1/models")
        case .ollama:           return URL(string: "\(Self.ollamaHost)/api/tags")
        case .foundationModels: return nil
        default:
            return openAIEndpoint.flatMap {
                URL(string: $0.absoluteString.replacingOccurrences(of: "chat/completions", with: "models"))
            }
        }
    }

    /// Default model id per provider. These move fast — update here if an API rejects the name.
    public var defaultModel: String {
        switch self {
        case .claude:           return "claude-sonnet-4-6"
        case .openAI:           return "gpt-5.4-mini"
        case .gemini:           return "gemini-3.5-flash"
        case .deepSeek:         return "deepseek-chat"
        case .grok:             return "grok-4.3"
        case .mistral:          return "mistral-large-latest"
        case .perplexity:       return "sonar"
        case .openRouter:       return "openai/gpt-5.4-mini"
        case .ollama:           return "llama3.2"
        case .foundationModels: return "on-device"
        // llama.cpp ignores the model name; LM Studio/vLLM replace it after Test Connection pulls
        // the server's real list. A visible placeholder beats an empty picker.
        case .custom1, .custom2: return "default"
        }
    }

    /// Suggested model ids for the picker. Just shortcuts — the user can type any id by hand,
    /// so an outdated list never blocks them.
    public var modelOptions: [String] {
        switch self {
        case .claude:           return ["claude-fable-5", "claude-opus-4-8", "claude-sonnet-4-6", "claude-haiku-4-5"]
        case .openAI:           return ["gpt-5.5", "gpt-5.4", "gpt-5.4-mini"]
        case .gemini:           return ["gemini-3.5-pro", "gemini-3.5-flash"]
        case .deepSeek:         return ["deepseek-chat", "deepseek-reasoner"]
        case .grok:             return ["grok-4.3", "grok-4.1-fast", "grok-4-fast-reasoning"]
        case .mistral:          return ["mistral-large-latest", "mistral-medium-latest", "mistral-small-latest"]
        case .perplexity:       return ["sonar", "sonar-pro", "sonar-reasoning"]
        case .openRouter:       return ["openai/gpt-5.4", "anthropic/claude-sonnet-4-6",
                                        "google/gemini-3.5-pro", "deepseek/deepseek-chat",
                                        "meta-llama/llama-4-70b-instruct"]
        case .ollama:           return ["llama3.2", "llama3.3", "qwen2.5", "deepseek-r1", "gemma3", "mistral", "phi4"]
        case .foundationModels: return ["on-device"]
        case .custom1, .custom2: return ["default"]
        }
    }

    /// Rough USD price per 1M tokens (input, output). Approximate — used only for a calm cost
    /// *estimate*; the user pays the provider directly with their own key. OpenRouter varies by
    /// model, so its number is a middling placeholder.
    public var pricePer1MInput: Double {
        switch self {
        case .claude:           return 3.0
        case .openAI:           return 2.5
        case .gemini:           return 0.3
        case .deepSeek:         return 0.3
        case .grok:             return 2.0
        case .mistral:          return 2.0
        case .perplexity:       return 1.0
        case .openRouter:       return 1.0
        case .ollama:           return 0
        case .foundationModels: return 0
        case .custom1, .custom2: return 0   // self-hosted
        }
    }
    public var pricePer1MOutput: Double {
        switch self {
        case .claude:           return 15.0
        case .openAI:           return 10.0
        case .gemini:           return 2.5
        case .deepSeek:         return 1.2
        case .grok:             return 10.0
        case .mistral:          return 6.0
        case .perplexity:       return 1.0
        case .openRouter:       return 3.0
        case .ollama:           return 0
        case .foundationModels: return 0
        case .custom1, .custom2: return 0   // self-hosted
        }
    }
}
