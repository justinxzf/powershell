import Foundation

struct ShellContext: Sendable {
    let cwd: String
    let shellType: ShellType
    let osInfo: String
    let recentHistory: [String]

    init(cwd: String, shellType: ShellType, osInfo: String = ProcessInfo.processInfo.operatingSystemVersionString, recentHistory: [String] = []) {
        self.cwd = cwd
        self.shellType = shellType
        self.osInfo = osInfo
        self.recentHistory = recentHistory
    }
}

struct CommandSuggestion: Sendable {
    let command: String
    let explanation: String?
    let isDangerous: Bool
}

enum NLStatus: Codable, Sendable {
    case detecting
    case converting
    case suggested
    case confirmed
    case cancelled
    case error(String)
}

struct NLRequest: Identifiable, Codable, Sendable {
    let id: UUID
    var input: String
    var suggestedCommand: String?
    var explanation: String?
    var isDangerous: Bool
    var status: NLStatus

    init(id: UUID = UUID(), input: String, suggestedCommand: String? = nil, explanation: String? = nil, isDangerous: Bool = false, status: NLStatus = .detecting) {
        self.id = id
        self.input = input
        self.suggestedCommand = suggestedCommand
        self.explanation = explanation
        self.isDangerous = isDangerous
        self.status = status
    }
}
