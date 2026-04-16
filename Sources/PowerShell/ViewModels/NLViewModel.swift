import Foundation
import Observation

@available(macOS 14.0, *)
@Observable
class NLViewModel {
    var currentRequest: NLRequest?
    var isConverting = false

    private let llmService: LLMService

    init(llmService: LLMService) {
        self.llmService = llmService
    }

    func processInput(_ input: String, context: ShellContext) async -> InputType {
        let inputType = NLDetector.detect(input)

        if inputType == .naturalLanguage {
            currentRequest = NLRequest(input: input)
            await convertToCommand(context: context)
        }

        return inputType
    }

    func confirmSuggestion() -> String? {
        guard let request = currentRequest, let command = request.suggestedCommand else { return nil }
        currentRequest = nil
        return command
    }

    func editSuggestion() -> String? {
        guard let request = currentRequest else { return nil }
        let command = request.suggestedCommand ?? request.input
        currentRequest = nil
        return command
    }

    func cancelSuggestion() {
        currentRequest = nil
    }

    private func convertToCommand(context: ShellContext) async {
        guard let request = currentRequest else { return }
        currentRequest?.status = .converting
        isConverting = true

        do {
            let suggestion = try await llmService.convert(
                naturalLanguage: request.input,
                context: context
            )
            currentRequest?.suggestedCommand = suggestion.command
            currentRequest?.explanation = suggestion.explanation
            currentRequest?.isDangerous = suggestion.isDangerous
            currentRequest?.status = .suggested
        } catch {
            currentRequest?.status = .error(error.localizedDescription)
        }

        isConverting = false
    }
}
