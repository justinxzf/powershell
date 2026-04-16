import Foundation

enum LLMProviderType: String, Codable, CaseIterable, Sendable {
    case anthropic
    case openAI

    var displayName: String {
        switch self {
        case .anthropic: return "Anthropic"
        case .openAI: return "OpenAI"
        }
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
