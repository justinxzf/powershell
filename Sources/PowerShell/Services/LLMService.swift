import Foundation

protocol LLMProviding: Sendable {
    func convert(naturalLanguage: String, context: ShellContext) async throws -> CommandSuggestion
}

class LLMService: LLMProviding, @unchecked Sendable {
    private var providers: [LLMProviderType: any LLMProviding] = [:]

    func registerProvider(_ type: LLMProviderType, provider: any LLMProviding) {
        providers[type] = provider
    }

    func convert(naturalLanguage: String, context: ShellContext) async throws -> CommandSuggestion {
        guard let provider = providers.values.first else {
            throw LLMError.noProviderConfigured
        }
        return try await provider.convert(naturalLanguage: naturalLanguage, context: context)
    }

    func convert(naturalLanguage: String, context: ShellContext, providerType: LLMProviderType) async throws -> CommandSuggestion {
        guard let provider = providers[providerType] else {
            throw LLMError.providerNotConfigured(providerType.rawValue)
        }
        return try await provider.convert(naturalLanguage: naturalLanguage, context: context)
    }

    enum LLMError: LocalizedError {
        case noProviderConfigured
        case providerNotConfigured(String)
        case invalidResponse
        case networkError(String)

        var errorDescription: String? {
            switch self {
            case .noProviderConfigured: return "No LLM provider configured"
            case .providerNotConfigured(let name): return "Provider '\(name)' not configured"
            case .invalidResponse: return "Invalid response from LLM API"
            case .networkError(let msg): return "Network error: \(msg)"
            }
        }
    }
}
