import Foundation

enum ShellType: String, CaseIterable, Codable {
    case bash = "/bin/bash"
    case zsh = "/bin/zsh"

    var displayName: String {
        switch self {
        case .bash: return "bash"
        case .zsh: return "zsh"
        }
    }
}

struct Session: Identifiable, Codable {
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
