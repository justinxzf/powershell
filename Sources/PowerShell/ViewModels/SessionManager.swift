import Foundation
import Observation

@available(macOS 14.0, *)
@MainActor
@Observable
class SessionManager {
    var sessions: [Session] = []
    var activeSessionId: UUID?

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
    }

    func rename(sessionId: UUID, newName: String) {
        if let index = sessions.firstIndex(where: { $0.id == sessionId }) {
            sessions[index].name = newName
        }
    }

    func delete(sessionId: UUID) {
        sessions.removeAll { $0.id == sessionId }
        if activeSessionId == sessionId {
            activeSessionId = sessions.first?.id
        }
    }

    func setActiveActivity(sessionId: UUID, isActive: Bool) {
        if let index = sessions.firstIndex(where: { $0.id == sessionId }) {
            sessions[index].isActive = isActive
        }
    }
}
