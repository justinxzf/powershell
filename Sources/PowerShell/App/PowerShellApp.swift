import SwiftUI
import SwiftTerm

struct WindowChromeConfiguration {
    let navigationTitle: String?
    let toolbarTitle: String
    let titlePlacement: ToolbarItemPlacement

    @MainActor
    static let app = WindowChromeConfiguration(
        navigationTitle: nil,
        toolbarTitle: "PowerShell",
        titlePlacement: .navigation
    )
}

@MainActor
protocol FullScreenToolbarPersisting: AnyObject {
    func apply(to window: NSWindow)
}

@MainActor
final class FullScreenToolbarConfigurator: NSObject, FullScreenToolbarPersisting, NSWindowDelegate {
    private weak var window: NSWindow?

    func apply(to window: NSWindow) {
        guard self.window !== window else {
            applyFullScreenToolbarPersistence(to: window)
            return
        }
        self.window?.delegate = nil
        self.window = window
        window.delegate = self
        applyFullScreenToolbarPersistence(to: window)
    }

    func windowWillEnterFullScreen(_ notification: Notification) {
        guard let window else { return }
        applyFullScreenToolbarPersistence(to: window)
    }

    private func applyFullScreenToolbarPersistence(to window: NSWindow) {
        window.toolbar?.showsBaselineSeparator = false
        window.toolbarStyle = .unifiedCompact
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
    }
}

@main
struct PowerShellApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var sessionManager = SessionManager()
    @State private var themeManager = ThemeManager()

    var body: some Scene {
        WindowGroup {
            RootContentView(
                sessionManager: sessionManager,
                themeManager: themeManager
            )
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
        .commands {
            CommandGroup(after: .newItem) {
                Button("New bash Session") {
                    _ = sessionManager.createSession(shellType: .bash)
                }
                Button("New zsh Session") {
                    _ = sessionManager.createSession(shellType: .zsh)
                }
            }
        }

        Settings {
            SettingsView(themeManager: themeManager)
        }
    }
}

private struct RootContentView: View {
    @Bindable var sessionManager: SessionManager
    let themeManager: ThemeManager
    private let chrome = WindowChromeConfiguration.app
    private let fullScreenToolbarConfigurator: FullScreenToolbarPersisting

    init(
        sessionManager: SessionManager,
        themeManager: ThemeManager,
        fullScreenToolbarConfigurator: FullScreenToolbarPersisting = FullScreenToolbarConfigurator()
    ) {
        self.sessionManager = sessionManager
        self.themeManager = themeManager
        self.fullScreenToolbarConfigurator = fullScreenToolbarConfigurator
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(sessionManager: sessionManager)
                .navigationTitle("")
        } detail: {
            ZStack {
                ForEach(sessionManager.sessions) { session in
                    TerminalDetailView(
                        session: session,
                        themeManager: themeManager,
                        isActive: session.id == sessionManager.activeSessionId,
                        onSessionActivityChanged: { isActive in
                            sessionManager.setActiveActivity(sessionId: session.id, isActive: isActive)
                        },
                        onDirectoryChanged: { directory in
                            sessionManager.updateDirectory(sessionId: session.id, directory: directory)
                        },
                        onAttentionNeeded: { type in
                            guard session.id != sessionManager.activeSessionId else { return }

                            switch type {
                            case .oscNotification(let title, let msg):
                                let body = "[\(session.name)] \(title): \(msg)"
                                NotificationManager.shared.send(
                                    title: "PowerShell",
                                    body: body,
                                    sessionId: session.id.uuidString
                                )
                                sessionManager.incrementUnread(sessionId: session.id)
                            }
                        },
                        onTerminalFocused: {
                            sessionManager.clearUnread(sessionId: session.id)
                        }
                    )
                    .opacity(session.id == sessionManager.activeSessionId ? 1 : 0)
                    .allowsHitTesting(session.id == sessionManager.activeSessionId)
                }

                if sessionManager.activeSession == nil {
                    VStack(spacing: 12) {
                        Image(systemName: "terminal")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text("No Active Session")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        Button("Create Session") {
                            _ = sessionManager.createSession()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(minWidth: 800, minHeight: 500)
        .navigationTitle("")
        .toolbar {
            ToolbarItem(placement: chrome.titlePlacement) {
                Text(chrome.toolbarTitle)
                    .fontWeight(.bold)
            }
        }
        .background(
            FullScreenToolbarPersistenceView(configurator: fullScreenToolbarConfigurator)
                .frame(width: 0, height: 0)
        )
        .onChange(of: sessionManager.activeSessionId) { _, newId in
            if let id = newId {
                sessionManager.clearUnread(sessionId: id)
            }
        }
        .task {
            NotificationManager.shared.onNotificationClicked = { sessionIdString in
                guard let sessionId = UUID(uuidString: sessionIdString) else { return }
                sessionManager.switchTo(sessionId: sessionId)
                NSApp.activate(ignoringOtherApps: true)
            }

            HookNotificationServer.shared.onHookNotification = { event in
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
            HookConfigurator.shared.configureIfNeeded()
            HookNotificationServer.shared.start()
            SkillInstaller.installIfNeeded()
        }
    }
}

private struct FullScreenToolbarPersistenceView: NSViewRepresentable {
    let configurator: FullScreenToolbarPersisting

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        configure(from: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        configure(from: nsView)
    }

    private func configure(from view: NSView) {
        guard let window = view.window else { return }
        configurator.apply(to: window)
    }
}

// MARK: - App Delegate

/// Ensures the app activates properly when launched from the command line.
/// Without this, the app runs as an .accessory and never receives keyboard events.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let appIconProvider: AppIconProviding

    override init() {
        self.appIconProvider = AppIconProvider()
        super.init()
    }

    init(appIconProvider: AppIconProviding) {
        self.appIconProvider = appIconProvider
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        appIconProvider.applyAppIcon()
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillBecomeActive(_ notification: Notification) {
        appIconProvider.applyAppIcon()
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Terminal Reference

/// A shared reference to the underlying InterceptingTerminalView,
/// allowing commands to be sent from the SwiftUI layer.
@MainActor
final class TerminalReference: ObservableObject {
    weak var terminalView: InterceptingTerminalView?

    func send(_ text: String) {
        guard let terminal = terminalView else { return }
        terminal.sendDirect(text)
    }

    func focus() {
        guard let terminal = terminalView,
              let window = terminal.window else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(terminal)
    }
}

// MARK: - Terminal Detail View

struct TerminalDetailView: View {
    let session: Session
    let themeManager: ThemeManager
    let isActive: Bool
    let onSessionActivityChanged: (Bool) -> Void
    var onDirectoryChanged: ((String?) -> Void)?
    var onAttentionNeeded: ((AttentionType) -> Void)?
    var onTerminalFocused: (() -> Void)?

    @StateObject private var terminalRef = TerminalReference()
    @State private var terminalTitle: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack(spacing: 8) {
                Circle()
                    .fill(session.isActive ? Color.green : Color.gray.opacity(0.5))
                    .frame(width: 8, height: 8)

                Text(terminalTitle.isEmpty ? session.name : terminalTitle)
                    .font(.body)
                    .lineLimit(1)

                Text(session.shellType.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.bar)

            Divider()

            TerminalPaneView(
                shellType: session.shellType,
                theme: themeManager.currentTheme,
                fontSize: FontSize(rawValue: UserDefaults.standard.string(forKey: "terminal_font_size") ?? "") ?? .medium,
                sessionId: session.id,
                onTitleChanged: { title in
                    Task { @MainActor in
                        terminalTitle = title
                    }
                },
                onDirectoryChanged: { directory in
                    Task { @MainActor in
                        onDirectoryChanged?(directory)
                    }
                },
                onProcessTerminated: { _ in
                    Task { @MainActor in
                        onSessionActivityChanged(false)
                    }
                },
                onTerminalCreated: { terminal in
                    Task { @MainActor in
                        terminalRef.terminalView = terminal

                        terminal.onAttentionNeeded = { type in
                            onAttentionNeeded?(type)
                        }

                        terminal.setupOutputMonitor()

                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            terminalRef.focus()
                        }
                    }
                },
                onFocus: {
                    onTerminalFocused?()
                }
            )
        }
        .onChange(of: isActive) { _, nowActive in
            if nowActive {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    terminalRef.focus()
                }
            }
        }
    }
}
