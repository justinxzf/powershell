import SwiftUI
import SwiftTerm

@MainActor
protocol PowerShellPlugin: AnyObject {

    // MARK: - Identity

    var pluginId: String { get }

    // MARK: - Lifecycle

    func setup(host: PluginManager)

    // MARK: - Hook Events

    func handleHookEvent(_ event: HookEvent, sessionManager: SessionManager)

    // MARK: - Session Terminal Lifecycle

    func terminalCreated(_ terminal: InterceptingTerminalView, session: Session)
    func directoryChanged(to directory: String?, session: Session)
    func processTerminated(session: Session)
    func terminalFocused(session: Session)

    // MARK: - Settings UI

    @ViewBuilder
    func settingsSection() -> (any View)?

    // MARK: - Skills

    var skillsDirectoryPath: String? { get }

    // MARK: - Layout & UI

    func sessionDidActivate(sessionId: UUID)
    func sessionWillDelete(sessionId: UUID)
    func overlayView(size: CGSize) -> AnyView?
    func headerAccessoryView(for session: Session, allSessions: [Session]) -> AnyView?
}

extension PowerShellPlugin {
    func handleHookEvent(_ event: HookEvent, sessionManager: SessionManager) {}
    func terminalCreated(_ terminal: InterceptingTerminalView, session: Session) {}
    func directoryChanged(to directory: String?, session: Session) {}
    func processTerminated(session: Session) {}
    func terminalFocused(session: Session) {}
    func settingsSection() -> (any View)? { nil }
    var skillsDirectoryPath: String? { nil }
    func sessionDidActivate(sessionId: UUID) {}
    func sessionWillDelete(sessionId: UUID) {}
    func overlayView(size: CGSize) -> AnyView? { nil }
    func headerAccessoryView(for session: Session, allSessions: [Session]) -> AnyView? { nil }
}
