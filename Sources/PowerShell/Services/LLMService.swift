import Foundation

protocol LLMProviding: Sendable {
    func convert(naturalLanguage: String, context: ShellContext) async throws -> CommandSuggestion
}

@MainActor
class LLMService: LLMProviding, @unchecked Sendable {
    private var providers: [LLMProviderType: any LLMProviding] = [:]
    var activeProviderType: LLMProviderType?

    func registerProvider(_ type: LLMProviderType, provider: any LLMProviding) {
        providers[type] = provider
        activeProviderType = type
    }

    func convert(naturalLanguage: String, context: ShellContext) async throws -> CommandSuggestion {
        if let type = activeProviderType, let provider = providers[type] {
            return try await provider.convert(naturalLanguage: naturalLanguage, context: context)
        }
        if let provider = providers.values.first {
            return try await provider.convert(naturalLanguage: naturalLanguage, context: context)
        }
        throw LLMError.noProviderConfigured
    }

    func convert(naturalLanguage: String, context: ShellContext, providerType: LLMProviderType) async throws -> CommandSuggestion {
        guard let provider = providers[providerType] else {
            throw LLMError.providerNotConfigured(providerType.rawValue)
        }
        return try await provider.convert(naturalLanguage: naturalLanguage, context: context)
    }

    /// Load saved config from UserDefaults + Keychain and register the provider
    func loadSavedConfig() {
        let providerTypeRaw = UserDefaults.standard.string(forKey: "llm_provider_type") ?? LLMProviderType.anthropic.rawValue
        guard let providerType = LLMProviderType(rawValue: providerTypeRaw) else { return }

        let apiKey = (try? KeychainService.load(key: providerType.keychainKey)) ?? ""
        guard !apiKey.isEmpty else { return }

        let model = UserDefaults.standard.string(forKey: "llm_model") ?? providerType.defaultModel
        let baseURL = UserDefaults.standard.string(forKey: "llm_base_url") ?? providerType.defaultBaseURL

        let provider = createProvider(type: providerType, apiKey: apiKey, model: model, baseURL: baseURL)
        registerProvider(providerType, provider: provider)
    }

    func createProvider(type: LLMProviderType, apiKey: String, model: String, baseURL: String) -> any LLMProviding {
        switch type {
        case .anthropic:
            return AnthropicProvider(apiKey: apiKey, model: model, baseURL: baseURL)
        case .openAI, .deepSeek:
            return OpenAIProvider(apiKey: apiKey, model: model, baseURL: baseURL)
        }
    }

    enum LLMError: LocalizedError {
        case noProviderConfigured
        case providerNotConfigured(String)
        case invalidResponse
        case networkError(String)

        var errorDescription: String? {
            switch self {
            case .noProviderConfigured: return "No LLM provider configured. Please configure one in Settings."
            case .providerNotConfigured(let name): return "Provider '\(name)' not configured"
            case .invalidResponse: return "Invalid response from LLM API"
            case .networkError(let msg): return "Network error: \(msg)"
            }
        }
    }
}
