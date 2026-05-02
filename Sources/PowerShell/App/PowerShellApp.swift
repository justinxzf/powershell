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
            SettingsView(
                themeManager: themeManager,
                pluginSettingsSections: PluginManager.shared.settingsSections()
            )
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
            PluginManager.shared.register(PluginRegistry.makePlugins())
            PluginManager.shared.runSetup()

            NotificationManager.shared.onNotificationClicked = { sessionIdString in
                guard let sessionId = UUID(uuidString: sessionIdString) else { return }
                sessionManager.switchTo(sessionId: sessionId)
                NSApp.activate(ignoringOtherApps: true)
            }

            HookEventRouter.wire(sessionManager: sessionManager)

            HookConfigurator.shared.configureIfNeeded()
            HookNotificationServer.shared.start()
            SkillInstaller.installIfNeeded()
            PluginManager.shared.installSkills()
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                ForEach(sessionManager.sessions) { session in
                    terminalPane(for: session, geoWidth: geo.size.width, geoHeight: geo.size.height)
                }

                if let overlay = PluginManager.shared.firstOverlayView(size: geo.size) {
                    overlay
                }

                if sessionManager.sessions.isEmpty {
                    emptyStateView
                }
            }
        }
    }

    @ViewBuilder
    private func terminalPane(for session: Session, geoWidth: CGFloat, geoHeight: CGFloat) -> some View {
        let sp = PluginManager.shared.splitPlugin
        let inLayout = sp?.splitLayout?.contains(session.id) ?? false
        let isPrimary = sp?.isPrimary(sessionId: session.id) ?? false
        let isSingleActive = sp?.splitLayout == nil && session.id == sessionManager.activeSessionId

        let frame: CGRect = sp?.paneFrame(for: session.id, W: geoWidth, H: geoHeight)
            ?? CGRect(x: 0, y: 0, width: geoWidth, height: geoHeight)

        let accessory = PluginManager.shared.firstHeaderAccessory(for: session, allSessions: sessionManager.sessions)

        TerminalDetailView(
            session: session,
            themeManager: themeManager,
            isActive: isSingleActive || isPrimary,
            onSessionActivityChanged: { isActive in
                sessionManager.setActiveActivity(sessionId: session.id, isActive: isActive)
                if !isActive {
                    PluginManager.shared.dispatchProcessTerminated(session: session)
                }
            },
            onDirectoryChanged: { directory in
                sessionManager.updateDirectory(sessionId: session.id, directory: directory)
                PluginManager.shared.dispatchDirectoryChanged(to: directory, session: session)
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
                PluginManager.shared.dispatchTerminalFocused(session: session)
            },
            headerAccessoryView: accessory
        )
        .frame(width: frame.width, height: frame.height)
        .offset(x: frame.minX, y: frame.minY)
        .opacity(isSingleActive || inLayout ? 1 : 0)
        .allowsHitTesting(isSingleActive || inLayout)
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

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if flag { return true }
        // SwiftUI's WindowGroup keeps closed windows alive internally. Find the existing
        // content window and re-show it instead of letting SwiftUI spawn a duplicate.
        if let window = sender.windows.first(where: { !$0.isVisible && !($0 is NSPanel) }) {
            window.makeKeyAndOrderFront(nil)
            return false
        }
        return true
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

struct TerminalHeaderPresentation: Equatable {
    let title: String

    init(session: Session, terminalTitle: String) {
        if let currentDirectory = session.currentDirectory, !currentDirectory.isEmpty {
            self.title = currentDirectory
        } else if !terminalTitle.isEmpty {
            self.title = terminalTitle
        } else {
            self.title = session.name
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
    var headerAccessoryView: AnyView? = nil

    @StateObject private var terminalRef = TerminalReference()
    @State private var terminalTitle: String = ""

    private var headerPresentation: TerminalHeaderPresentation {
        TerminalHeaderPresentation(session: session, terminalTitle: terminalTitle)
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

                if let accessory = headerAccessoryView {
                    accessory
                }
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
                        PluginManager.shared.dispatchTerminalCreated(terminal, session: session)

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
