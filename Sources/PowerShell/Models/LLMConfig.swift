import Foundation

enum LLMProviderType: String, CaseIterable, Codable {
    case anthropic
    case openAI

    var displayName: String {
        switch self {
        case .anthropic: return "Anthropic Claude"
        case .openAI: return "OpenAI GPT"
        }
    }

    var defaultModel: String {
        switch self {
        case .anthropic: return "claude-sonnet-4-6"
        case .openAI: return "gpt-4o"
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .anthropic: return "https://api.anthropic.com"
        case .openAI: return "https://api.openai.com"
        }
    }
}

struct LLMConfig: Codable {
    var providerType: LLMProviderType
    var apiKey: String
    var model: String
    var baseURL: String

    init(providerType: LLMProviderType = .anthropic, apiKey: String = "", model: String? = nil, baseURL: String? = nil) {
        self.providerType = providerType
        self.apiKey = apiKey
        self.model = model ?? providerType.defaultModel
        self.baseURL = baseURL ?? providerType.defaultBaseURL
    }
}
