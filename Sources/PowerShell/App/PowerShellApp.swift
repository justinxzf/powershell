import SwiftUI
import SwiftTerm

@main
struct PowerShellApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var sessionManager = SessionManager()
    @State private var nlViewModel: NLViewModel
    @State private var inputText = ""
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
                if let session = sessionManager.activeSession {
                    TerminalDetailView(
                        session: session,
                        nlViewModel: nlViewModel,
                        inputText: $inputText,
                        onSessionActivityChanged: { isActive in
                            sessionManager.setActiveActivity(sessionId: session.id, isActive: isActive)
                        }
                    )
                } else {
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
            .frame(minWidth: 800, minHeight: 500)
            .task {
                llmService.loadSavedConfig()
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
        // Ensure the app is properly activated for keyboard input
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Terminal Reference

/// A shared reference to the underlying LocalProcessTerminalView,
/// allowing commands to be sent from the SwiftUI layer.
@MainActor
final class TerminalReference: ObservableObject {
    weak var terminalView: LocalProcessTerminalView?

    func send(_ text: String) {
        guard let terminal = terminalView else { return }
        terminal.send(txt: text)
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
    @Binding var inputText: String
    let onSessionActivityChanged: (Bool) -> Void

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

            // Terminal
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
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            terminalRef.focus()
                        }
                    }
                }
            )

            Divider()

            // NL Input Bar
            NLInputBar(
                inputText: $inputText,
                nlRequest: nlViewModel.currentRequest,
                isConverting: nlViewModel.isConverting,
                onSubmit: { text in
                    handleSubmit(text)
                },
                onConfirmSuggestion: {
                    handleConfirmSuggestion()
                },
                onEditSuggestion: {
                    handleEditSuggestion()
                },
                onCancelSuggestion: {
                    nlViewModel.cancelSuggestion()
                }
            )
        }
    }

    private func handleSubmit(_ text: String) {
        let shellType = session.shellType
        let cwd = currentDirectory ?? NSHomeDirectory()

        Task {
            let context = ShellContext(
                cwd: cwd,
                shellType: shellType,
                recentHistory: []
            )

            let inputType = await nlViewModel.processInput(text, context: context)

            if inputType == .command {
                terminalRef.send(text + "\n")
            }

            // Return focus to the terminal after submitting
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                terminalRef.focus()
            }
        }
    }

    private func handleConfirmSuggestion() {
        guard let command = nlViewModel.confirmSuggestion() else { return }
        terminalRef.send(command + "\n")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            terminalRef.focus()
        }
    }

    private func handleEditSuggestion() {
        guard let command = nlViewModel.editSuggestion() else { return }
        inputText = command
    }

    private func focusTerminal() {
        terminalRef.focus()
    }
}
