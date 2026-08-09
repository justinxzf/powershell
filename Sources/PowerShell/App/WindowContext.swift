import AppKit
import Foundation

/// Per-window state container. Each PowerShell window owns its own
/// `SessionManager` and `PluginManager` so that sessions, terminals and
/// stateful plugins (split layout, chat list) are fully isolated between
/// windows. Only truly global services (hook server, notifications, hook
/// configuration, skill installation) are shared app-wide via `WindowRegistry`.
@MainActor
final class WindowContext: Identifiable {
    let id = UUID()
    let pluginHost: PluginManager
    let sessionManager: SessionManager

    /// The NSWindow hosting this context, resolved lazily once the view is
    /// attached. Used to bring the correct window to front when a notification
    /// is clicked or a hook event targets one of its sessions.
    weak var window: NSWindow?

    /// True while the hosting window is closed. Closed contexts are skipped
    /// when routing hook events / notifications.
    private(set) var isClosed = false

    private nonisolated(unsafe) var willCloseObserver: NSObjectProtocol?

    init() {
        let host = PluginManager()
        host.register(PluginRegistry.makePlugins())
        host.runSetup()
        self.pluginHost = host
        self.sessionManager = SessionManager(pluginHost: host)
    }

    deinit {
        if let willCloseObserver {
            NotificationCenter.default.removeObserver(willCloseObserver)
        }
    }

    /// Binds this context to its hosting window and starts observing its close
    /// event so the window's PTY processes can be reclaimed.
    func attach(to window: NSWindow) {
        guard self.window !== window else { return }
        self.window = window

        if let willCloseObserver {
            NotificationCenter.default.removeObserver(willCloseObserver)
        }
        willCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleWindowWillClose()
            }
        }
    }

    /// Terminates all shell processes owned by this window when it is closed.
    private func handleWindowWillClose() {
        guard !isClosed else { return }
        isClosed = true
        sessionManager.terminateAllSessions()
        DebugLog.write("[WindowContext] window closed, terminated sessions for context \(id)")
    }

    /// Recreates a fresh session when a previously-closed window is reopened
    /// (e.g. via the Dock), so the user never sees dead terminals.
    func reopenIfNeeded() {
        guard isClosed else { return }
        isClosed = false
        _ = sessionManager.createSession()
        DebugLog.write("[WindowContext] window reopened, created fresh session for context \(id)")
    }
}
