import Foundation

class OpenAIProvider: LLMProviding, @unchecked Sendable {
    private let apiKey: String
    private let model: String
    private let baseURL: String

    init(apiKey: String, model: String = "gpt-4o", baseURL: String = "https://api.openai.com") {
        self.apiKey = apiKey
        self.model = model
        self.baseURL = baseURL
    }

    func convert(naturalLanguage: String, context: ShellContext) async throws -> CommandSuggestion {
        let url = URL(string: "\(baseURL)/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let systemPrompt = """
        You are a command-line assistant. Convert the user's natural language request into a single shell command.
        Rules:
        - Output ONLY the command, nothing else. No explanation, no markdown, no backticks.
        - Target OS: macOS (\(context.osInfo))
        - Shell: \(context.shellType.displayName)
        - Current directory: \(context.cwd)
        - If the command is potentially dangerous (rm -rf, sudo, mkfs, dd, etc.), prefix your output with "DANGER:" followed by the command.
        - Prefer standard macOS/BSD commands over GNU/Linux-specific ones.
        """

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 256,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": naturalLanguage]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw LLMService.LLMError.networkError("HTTP \(statusCode)")
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let choices = json?["choices"] as? [[String: Any]]
        let message = choices?.first?["message"] as? [String: Any]
        let text = message?["content"] as? String ?? ""

        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let isDangerous = trimmedText.hasPrefix("DANGER:")
        let command = isDangerous ? String(trimmedText.dropFirst(7)).trimmingCharacters(in: .whitespaces) : trimmedText

        guard !command.isEmpty else {
            throw LLMService.LLMError.invalidResponse
        }

        return CommandSuggestion(command: command, explanation: nil, isDangerous: isDangerous)
    }
}
