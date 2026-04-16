import Foundation

enum InputType {
    case command
    case naturalLanguage
}

struct NLDetector {
    static func detect(_ input: String) -> InputType {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .command }

        // Check shell syntax first — contains pipe, redirect, variable, etc.
        let shellSyntaxChars: [Character] = ["|", ">", "<", "$", "~"]
        let shellSyntaxStrings = ["&&", "||", "--", "./"]
        if trimmed.contains(where: { shellSyntaxChars.contains($0) }) {
            return .command
        }
        if shellSyntaxStrings.contains(where: { trimmed.contains($0) }) {
            return .command
        }

        // Check if the first token is a known command (e.g. "git commit -m '中文'")
        let firstToken = trimmed.split(separator: " ", maxSplits: 1).first.map(String.init) ?? ""
        if Constants.knownCommands.contains(firstToken) {
            return .command
        }

        // Starts with a flag — command
        if trimmed.hasPrefix("-") {
            return .command
        }

        // Only check for natural language AFTER ruling out command patterns
        if trimmed.contains(where: { $0.isChineseCharacter }) {
            return .naturalLanguage
        }

        let lower = trimmed.lowercased()
        if Constants.nlSentencePatterns.contains(where: { lower.hasPrefix($0) }) {
            return .naturalLanguage
        }

        return .command
    }
}

extension Character {
    var isChineseCharacter: Bool {
        guard let scalar = unicodeScalars.first else { return false }
        return (0x4E00...0x9FFF).contains(scalar.value) ||
               (0x3400...0x4DBF).contains(scalar.value) ||
               (0x3000...0x303F).contains(scalar.value)
    }
}
