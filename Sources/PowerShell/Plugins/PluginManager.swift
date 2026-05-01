import SwiftUI

@Observable
@MainActor
final class PluginManager {

    static let shared = PluginManager()

    private var plugins: [any PowerShellPlugin] = []

    // SplitPlugin 在 setup() 时注册自身，供 RootContentView 直接观察
    private(set) var splitPlugin: SplitPlugin? = nil

    func registerSplitPlugin(_ plugin: SplitPlugin) {
        splitPlugin = plugin
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
        plugins.lazy.compactMap { $0.overlayView(size: size) }.first
    }

    func firstHeaderAccessory(for session: Session, allSessions: [Session]) -> AnyView? {
        plugins.lazy.compactMap { $0.headerAccessoryView(for: session, allSessions: allSessions) }.first
    }

    // MARK: - Settings UI

    func settingsSections() -> [AnyView] {
        plugins.compactMap { plugin in
            guard let section = plugin.settingsSection() else { return nil }
            return AnyView(section)
        }
    }
}
