import SwiftUI
import SwiftTerm

@main
struct PowerShellApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var sessionManager = SessionManager()
    @State private var nlViewModel: NLViewModel
    @State private var llmService = LLMService()

    init() {
        let service = LLMService()
        _llmService = State(initialValue: service)
        _nlViewModel = State(initialValue: NLViewModel(llmService: service))
    }

    var body: some Scene {
        WindowGroup {
            NavigationSplitView {
                SidebarView(sessionManager: sessionManager)
            } detail: {
                ZStack {
                    ForEach(sessionManager.sessions) { session in
                        TerminalDetailView(
                            session: session,
                            nlViewModel: nlViewModel,
                            isActive: session.id == sessionManager.activeSessionId,
                            onSessionActivityChanged: { isActive in
                                sessionManager.setActiveActivity(sessionId: session.id, isActive: isActive)
                            },
                            onDirectoryChanged: { directory in
                                sessionManager.updateDirectory(sessionId: session.id, directory: directory)
                            },
                            onAttentionNeeded: { type in
                                // Only notify when this session is NOT active (user is elsewhere)
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
            .onChange(of: sessionManager.activeSessionId) { _, newId in
                if let id = newId {
                    sessionManager.clearUnread(sessionId: id)
                }
            }
            .task {
                llmService.loadSavedConfig()
                NotificationManager.shared.requestAuthorization()
                NotificationManager.shared.onNotificationClicked = { sessionIdString in
                    guard let sessionId = UUID(uuidString: sessionIdString) else { return }
                    sessionManager.switchTo(sessionId: sessionId)
                }

                // Start hook notification server for Claude Code events
                HookNotificationServer.shared.onHookNotification = { event in
                    let claudeSessionId = event.session_id ?? ""

                    switch event.hook_event_name {
                    case "SessionStart":
                        sessionManager.handleClaudeSessionStart(claudeSessionId: claudeSessionId)
                    case "SessionEnd":
                        sessionManager.handleClaudeSessionEnd(claudeSessionId: claudeSessionId)
                    default:
                        let targetSessionId = sessionManager.sessionForClaudeSession(claudeSessionId)
                            ?? sessionManager.activeSessionId
                        let sessionName = targetSessionId.flatMap { id in
                            sessionManager.sessions.first(where: { $0.id == id })?.name
                        } ?? "终端"
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
                HookNotificationServer.shared.start()
            }
        }
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
            SettingsView(llmService: llmService)
        }
    }
}

// MARK: - App Delegate

/// Ensures the app activates properly when launched from the command line.
/// Without this, the app runs as an .accessory and never receives keyboard events.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillBecomeActive(_ notification: Notification) {
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
    @Bindable var nlViewModel: NLViewModel
    let isActive: Bool
    let onSessionActivityChanged: (Bool) -> Void
    var onDirectoryChanged: ((String?) -> Void)?
    var onAttentionNeeded: ((AttentionType) -> Void)?
    var onTerminalFocused: (() -> Void)?

    @StateObject private var terminalRef = TerminalReference()
    @State private var terminalTitle: String = ""
    @State private var currentDirectory: String?

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack(spacing: 8) {
                Circle()
                    .fill(session.isActive ? Color.green : Color.gray.opacity(0.5))
                    .frame(width: 8, height: 8)

                Text(terminalTitle.isEmpty ? session.name : terminalTitle)
                    .font(.headline)
                    .lineLimit(1)

                Text(session.shellType.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())

                Spacer()

                if nlViewModel.isConverting {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.bar)

            Divider()

            // Terminal with suggestion overlay
            ZStack(alignment: .bottom) {
                TerminalPaneView(
                    shellType: session.shellType,
                    onTitleChanged: { title in
                        Task { @MainActor in
                            terminalTitle = title
                        }
                    },
                    onDirectoryChanged: { directory in
                        Task { @MainActor in
                            currentDirectory = directory
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

                            terminal.onLineEntered = { line in
                                handleLineEntered(line)
                            }

                            terminal.onSuggestionAction = { action in
                                switch action {
                                case .confirm:
                                    handleConfirmSuggestion()
                                case .cancel:
                                    nlViewModel.cancelSuggestion()
                                }
                            }

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

                // NL suggestion overlay
                if let request = nlViewModel.currentRequest {
                    suggestionOverlay(for: request)
                }
            }
        }
        .onChange(of: isActive) { _, nowActive in
            if nowActive {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    terminalRef.focus()
                }
            }
        }
        .onChange(of: session.claudeCodeActive) { _, active in
            terminalRef.terminalView?.skipNLDetection = active
        }
    }

    @ViewBuilder
    private func suggestionOverlay(for request: NLRequest) -> some View {
        switch request.status {
        case .converting:
            HStack {
                ProgressView()
                    .controlSize(.small)
                Text("正在转换...")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.85))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .padding(8)

        case .suggested:
            CommandSuggestionView(
                request: request,
                onConfirm: { handleConfirmSuggestion() },
                onEdit: { handleEditSuggestion() },
                onCancel: { nlViewModel.cancelSuggestion() },
                onExecuteOriginal: { handleExecuteOriginal() },
                darkStyle: true
            )
            .padding(8)

        case .error(let message):
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                Spacer()
                Button("取消") { nlViewModel.cancelSuggestion() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.85))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .padding(8)

        default:
            EmptyView()
        }
    }

    private func handleLineEntered(_ line: String) {
        let shellType = session.shellType
        let cwd = currentDirectory ?? NSHomeDirectory()

        Task {
            let context = ShellContext(
                cwd: cwd,
                shellType: shellType,
                recentHistory: []
            )
            _ = await nlViewModel.processInput(line, context: context)

            // Mark the terminal as having an active suggestion so Enter confirms it
            if let status = nlViewModel.currentRequest?.status,
               case .suggested = status {
                terminalRef.terminalView?.hasActiveSuggestion = true
            }
        }
    }

    private func handleConfirmSuggestion() {
        guard let command = nlViewModel.confirmSuggestion() else { return }
        terminalRef.terminalView?.hasActiveSuggestion = false
        terminalRef.send(command + "\n")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            terminalRef.focus()
        }
    }

    private func handleEditSuggestion() {
        guard let _ = nlViewModel.editSuggestion() else { return }
        nlViewModel.cancelSuggestion()
        terminalRef.terminalView?.hasActiveSuggestion = false
    }

    private func handleExecuteOriginal() {
        guard let request = nlViewModel.currentRequest else { return }
        let original = request.input
        nlViewModel.cancelSuggestion()
        terminalRef.terminalView?.hasActiveSuggestion = false
        terminalRef.send(original + "\n")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            terminalRef.focus()
        }
    }
}
