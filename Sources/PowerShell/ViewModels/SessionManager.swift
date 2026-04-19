import Foundation
import Observation

@available(macOS 14.0, *)
@MainActor
@Observable
class SessionManager {
    var sessions: [Session] = []
    var activeSessionId: UUID?
    var unreadCounts: [UUID: Int] = [:]

    // Maps Claude Code session_id → app Session UUID
    private var claudeSessionMap: [String: UUID] = [:]

    init() {
        _ = createSession()
    }

    var activeSession: Session? {
        sessions.first { $0.id == activeSessionId }
    }

    func createSession(name: String? = nil, shellType: ShellType = .zsh) -> Session {
        let sessionName = name ?? "终端 \(sessions.count + 1)"
        let session = Session(name: sessionName, shellType: shellType)
        sessions.append(session)
        if activeSessionId == nil {
            activeSessionId = session.id
        }
        return session
    }

    func switchTo(sessionId: UUID) {
        guard sessions.contains(where: { $0.id == sessionId }) else { return }
        activeSessionId = sessionId
        clearUnread(sessionId: sessionId)
    }

    func rename(sessionId: UUID, newName: String) {
        if let index = sessions.firstIndex(where: { $0.id == sessionId }) {
            sessions[index].name = newName
            sessions[index].needsRename = false
        }
    }

    func startRenaming(sessionId: UUID) {
        if let index = sessions.firstIndex(where: { $0.id == sessionId }) {
            sessions[index].needsRename = true
        }
    }

    func delete(sessionId: UUID) {
        sessions.removeAll { $0.id == sessionId }
        if activeSessionId == sessionId {
            activeSessionId = sessions.first?.id
        }
        claudeSessionMap = claudeSessionMap.filter { $0.value != sessionId }
    }

    func setActiveActivity(sessionId: UUID, isActive: Bool) {
        if let index = sessions.firstIndex(where: { $0.id == sessionId }) {
            sessions[index].isActive = isActive
        }
    }

    func updateDirectory(sessionId: UUID, directory: String?) {
        if let index = sessions.firstIndex(where: { $0.id == sessionId }) {
            sessions[index].currentDirectory = directory
        }
    }

    func incrementUnread(sessionId: UUID) {
        unreadCounts[sessionId, default: 0] += 1
    }

    func clearUnread(sessionId: UUID) {
        unreadCounts.removeValue(forKey: sessionId)
    }

    // MARK: - Claude Code session tracking

    func handleClaudeSessionStart(claudeSessionId: String) {
        guard let sessionId = activeSessionId else { return }
        claudeSessionMap[claudeSessionId] = sessionId
        if let index = sessions.firstIndex(where: { $0.id == sessionId }) {
            sessions[index].claudeCodeActive = true
        }
    }

    func handleClaudeSessionEnd(claudeSessionId: String) {
        guard let sessionId = claudeSessionMap.removeValue(forKey: claudeSessionId) else { return }
        if let index = sessions.firstIndex(where: { $0.id == sessionId }) {
            sessions[index].claudeCodeActive = false
        }
    }

    func sessionForClaudeSession(_ claudeSessionId: String) -> UUID? {
        claudeSessionMap[claudeSessionId]
    }

    func sessionForCwd(_ cwd: String) -> UUID? {
        sessions.first { $0.currentDirectory == cwd }?.id
    }

}
