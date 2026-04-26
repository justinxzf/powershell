import SwiftUI
import SwiftTerm

@MainActor
protocol PowerShellPlugin: AnyObject {

    // MARK: - Identity

    var pluginId: String { get }

    // MARK: - Lifecycle

    func setup()

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
}

extension PowerShellPlugin {
    func handleHookEvent(_ event: HookEvent, sessionManager: SessionManager) {}
    func terminalCreated(_ terminal: InterceptingTerminalView, session: Session) {}
    func directoryChanged(to directory: String?, session: Session) {}
    func processTerminated(session: Session) {}
    func terminalFocused(session: Session) {}
    func settingsSection() -> (any View)? { nil }
    var skillsDirectoryPath: String? { nil }
}
