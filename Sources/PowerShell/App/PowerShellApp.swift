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
            detailContent
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

    @ViewBuilder
    private var detailContent: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                ForEach(sessionManager.sessions) { session in
                    terminalPane(for: session, geoWidth: geo.size.width, geoHeight: geo.size.height)
                }

                if sessionManager.splitPair != nil {
                    SplitDividerView(
                        ratio: $sessionManager.splitRatio,
                        totalWidth: geo.size.width
                    )
                }

                if sessionManager.sessions.isEmpty {
                    emptyStateView
                }
            }
        }
    }

    @ViewBuilder
    private func terminalPane(for session: Session, geoWidth: CGFloat, geoHeight: CGFloat) -> some View {
        let isPrimary = sessionManager.splitPair?.primary == session.id
        let isSecondary = sessionManager.splitPair?.secondary == session.id
        let isInSplit = isPrimary || isSecondary
        let isSingleActive = sessionManager.splitPair == nil && session.id == sessionManager.activeSessionId

        let paneW: CGFloat = {
            if isPrimary { return geoWidth * sessionManager.splitRatio }
            if isSecondary { return geoWidth * (1 - sessionManager.splitRatio) }
            return geoWidth
        }()

        let paneX: CGFloat = isSecondary ? geoWidth * sessionManager.splitRatio : 0

        let secName: String? = isPrimary
            ? sessionManager.sessions.first(where: { $0.id == sessionManager.splitPair?.secondary })?.name
            : nil

        TerminalDetailView(
            session: session,
            themeManager: themeManager,
            isActive: isSingleActive || isPrimary,
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
            },
            isSplitPrimary: isPrimary,
            isSplitSecondary: isSecondary,
            splitSecondaryName: secName,
            allSessions: sessionManager.sessions,
            onSplitRequested: { primaryId, secondaryId in
                guard sessionManager.splitPair == nil else { return }
                sessionManager.split(primary: primaryId, secondary: secondaryId)
            },
            onUnsplit: { sessionManager.unsplit() }
        )
        .frame(width: paneW, height: geoHeight)
        .offset(x: paneX)
        .opacity(isSingleActive || isInSplit ? 1 : 0)
        .allowsHitTesting(isSingleActive || isInSplit)
    }

    private var emptyStateView: some View {
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

enum TerminalHeaderAccessory: Equatable {
    case splitMenu
    case splitSummary(String)
    case none
}

struct TerminalHeaderPresentation: Equatable {
    let title: String
    let accessory: TerminalHeaderAccessory

    init(session: Session, terminalTitle: String, splitSecondaryName: String?, isSplitSecondary: Bool) {
        if let currentDirectory = session.currentDirectory, !currentDirectory.isEmpty {
            self.title = currentDirectory
        } else if !terminalTitle.isEmpty {
            self.title = terminalTitle
        } else {
            self.title = session.name
        }

        if isSplitSecondary {
            self.accessory = .none
        } else if let splitSecondaryName, !splitSecondaryName.isEmpty {
            self.accessory = .splitSummary(splitSecondaryName)
        } else {
            self.accessory = .splitMenu
        }
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
    var isSplitPrimary: Bool = false
    var isSplitSecondary: Bool = false
    var splitSecondaryName: String? = nil
    var allSessions: [Session] = []
    var onSplitRequested: ((UUID, UUID) -> Void)? = nil
    var onUnsplit: (() -> Void)? = nil

    @StateObject private var terminalRef = TerminalReference()
    @State private var terminalTitle: String = ""

    private var headerPresentation: TerminalHeaderPresentation {
        TerminalHeaderPresentation(
            session: session,
            terminalTitle: terminalTitle,
            splitSecondaryName: splitSecondaryName,
            isSplitSecondary: isSplitSecondary
        )
    }

    private var availableSessionsForSplit: [Session] {
        allSessions.filter { $0.id != session.id }
    }

    @ViewBuilder
    private var headerAccessory: some View {
        switch headerPresentation.accessory {
        case .splitSummary(let secName):
            Text("│")
                .foregroundStyle(.tertiary)
            Text(secName)
                .font(.caption)
                .foregroundStyle(.secondary)
            Button {
                onUnsplit?()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("取消分屏")
        case .splitMenu:
            Menu {
                ForEach(availableSessionsForSplit, id: \.id) { s in
                    Button(s.name) {
                        onSplitRequested?(session.id, s.id)
                    }
                }
            } label: {
                Image(systemName: "rectangle.split.2x1")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .help("分屏显示另一个终端")
        case .none:
            EmptyView()
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Circle()
                    .fill(session.isActive ? Color.green : Color.gray.opacity(0.5))
                    .frame(width: 8, height: 8)

                Text(headerPresentation.title)
                    .font(.body)
                    .lineLimit(1)

                Text(session.shellType.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())

                Spacer()

                headerAccessory
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
