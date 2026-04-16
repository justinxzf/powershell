import Foundation

enum NLStatus {
    case detecting
    case converting
    case suggested
    case confirmed
    case cancelled
    case error(String)
}

struct NLRequest {
    var input: String
    var suggestedCommand: String?
    var explanation: String?
    var isDangerous: Bool
    var status: NLStatus

    init(input: String) {
        self.input = input
        self.suggestedCommand = nil
        self.explanation = nil
        self.isDangerous = false
        self.status = .detecting
    }
}

struct ShellContext {
    let cwd: String
    let shellType: ShellType
    let osInfo: String
    let recentHistory: [String]

    static var current: ShellContext {
        ShellContext(
            cwd: FileManager.default.currentDirectoryPath,
            shellType: .zsh,
            osInfo: ProcessInfo.processInfo.operatingSystemVersionString,
            recentHistory: []
        )
    }
}

struct CommandSuggestion {
    let command: String
    let explanation: String?
    let isDangerous: Bool
}
