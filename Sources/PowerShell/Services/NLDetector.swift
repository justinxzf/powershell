import Foundation

enum InputType {
    case command
    case naturalLanguage
}

struct NLDetector {
    static func detect(_ input: String) -> InputType {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .command }

        if trimmed.contains(where: { $0.isChineseCharacter }) {
            return .naturalLanguage
        }

        let lower = trimmed.lowercased()
        if Constants.nlSentencePatterns.contains(where: { lower.hasPrefix($0) }) {
            return .naturalLanguage
        }

        let firstToken = trimmed.split(separator: " ", maxSplits: 1).first.map(String.init) ?? ""
        if Constants.knownCommands.contains(firstToken) {
            return .command
        }

        let shellSyntaxPatterns: [Character] = ["|", ">", "<", "$", "~"]
        let shellSyntaxStrings = ["&&", "||", "--", "./"]
        if trimmed.contains(where: { shellSyntaxPatterns.contains($0) }) {
            return .command
        }
        if shellSyntaxStrings.contains(where: { trimmed.contains($0) }) {
            return .command
        }
        if trimmed.hasPrefix("-") {
            return .command
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
