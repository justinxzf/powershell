import Foundation

@MainActor
enum HookEventRouter {

    static func wire(sessionManager: SessionManager) {
        HookNotificationServer.shared.onHookNotification = { event in
            coreRoute(event: event, sessionManager: sessionManager)
            PluginManager.shared.dispatchHookEvent(event, sessionManager: sessionManager)
        }
    }

    private static func coreRoute(event: HookEvent, sessionManager: SessionManager) {
        let claudeSessionId = event.session_id ?? ""
        DebugLog.write("[HookRouter] event=\(event.hook_event_name), session_id=\(claudeSessionId), type=\(event.notification_type ?? "nil"), psid=\(event.powershell_session_id ?? "nil")")

        switch event.hook_event_name {
        case "SessionStart":
            sessionManager.handleClaudeSessionStart(
                claudeSessionId: claudeSessionId,
                powershellSessionId: event.powershell_session_id
            )
        case "SessionEnd":
            sessionManager.handleClaudeSessionEnd(
                claudeSessionId: claudeSessionId,
                powershellSessionId: event.powershell_session_id
            )
        default:
            let targetSessionId: UUID?
            if let psid = event.powershell_session_id {
                targetSessionId = sessionManager.sessionForPowershellSession(psid)
                    ?? sessionManager.sessionForClaudeSession(claudeSessionId)
                    ?? sessionManager.activeSessionId
            } else {
                targetSessionId = sessionManager.sessionForClaudeSession(claudeSessionId)
                    ?? sessionManager.activeSessionId
            }
            let sessionName = targetSessionId.flatMap { id in
                sessionManager.sessions.first(where: { $0.id == id })?.name
            } ?? "终端"
            DebugLog.write("[HookRouter] sending notification: targetSession=\(targetSessionId?.uuidString ?? "nil"), name=\(sessionName)")
            NotificationManager.shared.send(
                title: "PowerShell [\(sessionName)]",
                body: event.displayMessage,
                sessionId: targetSessionId?.uuidString ?? ""
            )
            if let id = targetSessionId, id != sessionManager.activeSessionId {
                sessionManager.incrementUnread(sessionId: id)
            }
        }
    }
}
