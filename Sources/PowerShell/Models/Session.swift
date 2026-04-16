import Foundation

enum ShellType: String, Codable, CaseIterable, Sendable {
    case bash
    case zsh

    var displayName: String {
        switch self {
        case .bash: return "bash"
        case .zsh: return "zsh"
        }
    }

    var launchPath: String {
        switch self {
        case .bash: return "/bin/bash"
        case .zsh: return "/bin/zsh"
        }
    }
}

struct Session: Identifiable, Codable, Sendable {
    let id: UUID
    var name: String
    var shellType: ShellType
    var isActive: Bool

    init(id: UUID = UUID(), name: String, shellType: ShellType = .zsh, isActive: Bool = false) {
        self.id = id
        self.name = name
        self.shellType = shellType
        self.isActive = isActive
    }
}

struct TerminalState: Codable, Sendable {
    var buffer: String
    var cursorPosition: Int
    var commandHistory: [String]

    init(buffer: String = "", cursorPosition: Int = 0, commandHistory: [String] = []) {
        self.buffer = buffer
        self.cursorPosition = cursorPosition
        self.commandHistory = commandHistory
    }
}
