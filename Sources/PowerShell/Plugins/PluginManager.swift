import SwiftUI

@Observable
@MainActor
final class PluginManager {

    static let shared = PluginManager()

    private var plugins: [any PowerShellPlugin] = []

    // Buffer of terminals created before plugins were registered, for replay on setup.
    private var pendingTerminalEvents: [(terminal: InterceptingTerminalView, session: Session)] = []

    // SplitPlugin 在 setup() 时注册自身，供 RootContentView 直接观察
    private(set) var splitPlugin: SplitPlugin? = nil

    func registerSplitPlugin(_ plugin: SplitPlugin) {
        splitPlugin = plugin
    }

    // ChatListPlugin 在 setup() 时注册自身，绕过existential以保证SwiftUI观察
    private(set) var chatListPlugin: ChatListPlugin? = nil

    func registerChatListPlugin(_ plugin: ChatListPlugin) {
        chatListPlugin = plugin
        for (terminal, session) in pendingTerminalEvents {
            plugin.terminalCreated(terminal, session: session)
        }
    }

    func register(_ plugins: [any PowerShellPlugin]) {
        self.plugins = plugins
        for plugin in plugins {
            DebugLog.write("[PluginManager] registered: \(plugin.pluginId)")
        }
    }

    func runSetup() {
        for plugin in plugins {
            plugin.setup()
        }
    }

    func installSkills() {
        for plugin in plugins {
            guard let path = plugin.skillsDirectoryPath else { continue }
            SkillInstaller.installIfNeeded(skillsDirectoryPath: path)
        }
    }

    // MARK: - Hook Event Dispatch

    func dispatchHookEvent(_ event: HookEvent, sessionManager: SessionManager) {
        for plugin in plugins {
            plugin.handleHookEvent(event, sessionManager: sessionManager)
        }
    }

    // MARK: - Session Lifecycle Dispatch

    func dispatchTerminalCreated(_ terminal: InterceptingTerminalView, session: Session) {
        pendingTerminalEvents.append((terminal, session))
        for plugin in plugins {
            plugin.terminalCreated(terminal, session: session)
        }
    }

    func dispatchDirectoryChanged(to directory: String?, session: Session) {
        for plugin in plugins {
            plugin.directoryChanged(to: directory, session: session)
        }
    }

    func dispatchProcessTerminated(session: Session) {
        for plugin in plugins {
            plugin.processTerminated(session: session)
        }
    }

    func dispatchTerminalFocused(session: Session) {
        for plugin in plugins {
            plugin.terminalFocused(session: session)
        }
    }

    func dispatchSessionDidActivate(sessionId: UUID) {
        for plugin in plugins {
            plugin.sessionDidActivate(sessionId: sessionId)
        }
    }

    func dispatchSessionWillDelete(sessionId: UUID) {
        for plugin in plugins {
            plugin.sessionWillDelete(sessionId: sessionId)
        }
    }

    // MARK: - Layout & UI

    func firstOverlayView(size: CGSize) -> AnyView? {
        var views: [AnyView] = plugins.compactMap { plugin in
            guard !(plugin is ChatListPlugin) else { return nil }
            return plugin.overlayView(size: size)
        }
        if let view = chatListPlugin?.overlayView(size: size) {
            views.append(view)
        }
        guard !views.isEmpty else { return nil }
        return AnyView(
            ZStack(alignment: .topLeading) {
                ForEach(Array(views.enumerated()), id: \.offset) { _, view in view }
            }
        )
    }

    func firstHeaderAccessory(for session: Session, allSessions: [Session]) -> AnyView? {
        var views: [AnyView] = plugins.compactMap { plugin in
            guard !(plugin is ChatListPlugin) else { return nil }
            return plugin.headerAccessoryView(for: session, allSessions: allSessions)
        }
        if let view = chatListPlugin?.headerAccessoryView(for: session, allSessions: allSessions) {
            views.append(view)
        }
        guard !views.isEmpty else { return nil }
        return AnyView(
            HStack(spacing: 4) {
                ForEach(Array(views.enumerated()), id: \.offset) { _, view in view }
            }
        )
    }

    // MARK: - Settings UI

    func settingsSections() -> [AnyView] {
        plugins.compactMap { plugin in
            guard let section = plugin.settingsSection() else { return nil }
            return AnyView(section)
        }
    }
}
