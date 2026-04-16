import Foundation

enum LLMProviderType: String, Codable, CaseIterable, Sendable {
    case anthropic
    case openAI
    case deepSeek

    var displayName: String {
        switch self {
        case .anthropic: return "Anthropic"
        case .openAI: return "OpenAI"
        case .deepSeek: return "DeepSeek"
        }
    }

    var defaultModel: String {
        switch self {
        case .anthropic: return "claude-sonnet-4-20250514"
        case .openAI: return "gpt-4o"
        case .deepSeek: return "deepseek-chat"
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .anthropic: return "https://api.anthropic.com"
        case .openAI: return "https://api.openai.com"
        case .deepSeek: return "https://api.deepseek.com"
        }
    }

    var keychainKey: String {
        "llm_api_key_\(rawValue)"
    }
}

struct LLMConfig: Codable, Sendable {
    var provider: LLMProviderType
    var apiKey: String
    var model: String

    init(provider: LLMProviderType, apiKey: String, model: String) {
        self.provider = provider
        self.apiKey = apiKey
        self.model = model
    }
}
