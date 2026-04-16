import SwiftUI
import SwiftTerm

@main
struct PowerShellApp: App {
    @State private var sessionManager = SessionManager()
    @State private var nlViewModel: NLViewModel
    @State private var inputText = ""

    init() {
        let llmService = LLMService()
        _nlViewModel = State(initialValue: NLViewModel(llmService: llmService))
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
            SettingsView()
        }
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
        let data = ArraySlice(text.data(using: .utf8) ?? Data())
        terminal.process.send(data: data)
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
                }
            )
            .overlay {
                GeometryReader { proxy in
                    Color.clear
                        .onAppear {
                            findTerminalView(in: proxy)
                        }
                }
            }

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
            // If naturalLanguage, NLViewModel will set currentRequest and
            // NLInputBar will display the suggestion via CommandSuggestionView.
        }
    }

    private func handleConfirmSuggestion() {
        guard let command = nlViewModel.confirmSuggestion() else { return }
        terminalRef.send(command + "\n")
    }

    private func handleEditSuggestion() {
        guard let command = nlViewModel.editSuggestion() else { return }
        inputText = command
    }

    /// Walk the view hierarchy to find the LocalProcessTerminalView NSView
    /// and store it in our TerminalReference.
    private func findTerminalView(in proxy: GeometryProxy) {
        guard let window = NSApp.windows.first(where: { $0.isVisible }),
              let contentView = window.contentView else { return }

        if let terminal = findLocalProcessTerminalView(in: contentView) {
            terminalRef.terminalView = terminal
        }
    }

    private func findLocalProcessTerminalView(in view: NSView) -> LocalProcessTerminalView? {
        if let terminal = view as? LocalProcessTerminalView {
            return terminal
        }
        for subview in view.subviews {
            if let found = findLocalProcessTerminalView(in: subview) {
                return found
            }
        }
        return nil
    }
}
