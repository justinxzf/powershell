import AppKit
import Foundation

/// App-wide registry of open windows. Owns one-time global service setup and
/// routes incoming hook events / notification clicks to the correct window's
/// `SessionManager` and `PluginManager`.
@MainActor
final class WindowRegistry {
    static let shared = WindowRegistry()

    private(set) var contexts: [WindowContext] = []
    private var didConfigureGlobals = false

    // MARK: - Registration

    func register(_ ctx: WindowContext) {
        guard !contexts.contains(where: { $0 === ctx }) else { return }
        contexts.append(ctx)
        DebugLog.write("[WindowRegistry] registered context \(ctx.id), total=\(contexts.count)")
    }

    func unregister(_ ctx: WindowContext) {
        contexts.removeAll { $0 === ctx }
        DebugLog.write("[WindowRegistry] unregistered context \(ctx.id), total=\(contexts.count)")
    }

    /// The context of the currently focused window, falling back to the first
    /// open window. Used by menu commands that act on "the current window".
    var keyOrFirstContext: WindowContext? {
        let open = contexts.filter { !$0.isClosed }
        return open.first(where: { $0.window?.isKeyWindow == true }) ?? open.first
    }

    /// Re-initializes a previously-closed window when it is reopened (e.g. via
    /// the Dock) so it comes back with a fresh session instead of dead terminals.
    func reopenContext(for window: NSWindow) {
        contexts.first(where: { $0.window === window })?.reopenIfNeeded()
    }

    // MARK: - One-time global setup

    /// Configures shared services exactly once, regardless of how many windows
    /// are opened. Safe to call multiple times.
    func configureGlobalsIfNeeded() {
        guard !didConfigureGlobals else { return }
        didConfigureGlobals = true

        NotificationManager.shared.onNotificationClicked = { sessionIdString in
            WindowRegistry.shared.handleNotificationClick(sessionIdString)
        }

        HookNotificationServer.shared.onHookNotification = { event in
            WindowRegistry.shared.routeHookEvent(event)
        }

        HookConfigurator.shared.configureIfNeeded()
        HookNotificationServer.shared.start()

        SkillInstaller.installIfNeeded()
        for plugin in PluginRegistry.makePlugins() {
            guard let path = plugin.skillsDirectoryPath else { continue }
            SkillInstaller.installIfNeeded(skillsDirectoryPath: path)
        }

        DebugLog.write("[WindowRegistry] global services configured")
    }

    // MARK: - Routing

    func routeHookEvent(_ event: HookEvent) {
        guard let ctx = contextForHookEvent(event) else {
            DebugLog.write("[WindowRegistry] no window to route hook event \(event.hook_event_name)")
            return
        }
        HookEventRouter.coreRoute(event: event, sessionManager: ctx.sessionManager)
        ctx.pluginHost.dispatchHookEvent(event, sessionManager: ctx.sessionManager)
    }

    func handleNotificationClick(_ sessionIdString: String) {
        guard let sessionId = UUID(uuidString: sessionIdString) else { return }
        guard let ctx = contexts.first(where: { ctx in
            !ctx.isClosed && ctx.sessionManager.sessions.contains(where: { $0.id == sessionId })
        }) else { return }
        ctx.sessionManager.switchTo(sessionId: sessionId)
        NSApp.activate(ignoringOtherApps: true)
        ctx.window?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Helpers

    private func contextForHookEvent(_ event: HookEvent) -> WindowContext? {
        let open = contexts.filter { !$0.isClosed }

        // Prefer the window that owns the originating PowerShell session — this
        // uniquely identifies a window because POWERSHELL_SESSION_ID is injected
        // per PTY and each session lives in exactly one window.
        if let psid = event.powershell_session_id,
           let ctx = open.first(where: { $0.sessionManager.sessionForPowershellSession(psid) != nil }) {
            return ctx
        }

        let claudeId = event.session_id ?? ""
        if !claudeId.isEmpty,
           let ctx = open.first(where: { $0.sessionManager.sessionForClaudeSession(claudeId) != nil }) {
            return ctx
        }

        // Fallback: the key window, otherwise the first open window.
        return open.first(where: { $0.window?.isKeyWindow == true }) ?? open.first
    }
}
