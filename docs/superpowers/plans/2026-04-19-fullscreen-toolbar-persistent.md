# Fullscreen Persistent Toolbar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep the top toolbar visible at all times in fullscreen while preserving the fixed `PowerShell` toolbar title and existing terminal behavior.

**Architecture:** Keep the change local to `PowerShellApp.swift`. Remove the fullscreen-specific toolbar auto-hide mechanism and its tracking hooks so the macOS window toolbar stays visible in both normal and fullscreen modes, while preserving the existing principal toolbar title and terminal/session logic.

**Tech Stack:** Swift 6, SwiftUI, AppKit, XCTest, Swift Package Manager

---

## File Structure

- Modify: `Sources/PowerShell/App/PowerShellApp.swift` — remove fullscreen hover-driven toolbar visibility management while preserving the toolbar title and window behavior otherwise
- Modify: `Tests/PowerShellTests/PowerShellAppTitleBarTests.swift` — extend the focused window-chrome test seam to assert fullscreen toolbar persistence intent

This plan keeps the change in the existing app file and the existing focused title-bar test file. No new production files are needed.

---

### Task 1: Remove fullscreen toolbar auto-hide

**Files:**
- Modify: `Sources/PowerShell/App/PowerShellApp.swift:1-360`
- Test: `Tests/PowerShellTests/PowerShellAppTitleBarTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
import SwiftUI
@testable import PowerShell

final class PowerShellAppTitleBarTests: XCTestCase {
    @MainActor
    func testWindowChromeConfigurationKeepsToolbarVisibleInFullscreen() {
        XCTAssertNil(WindowChromeConfiguration.navigationTitle)
        XCTAssertEqual(WindowChromeConfiguration.toolbarTitle, "PowerShell")
        XCTAssertEqual(
            String(describing: WindowChromeConfiguration.titlePlacement),
            String(describing: ToolbarItemPlacement.principal)
        )
        XCTAssertTrue(WindowChromeConfiguration.fullscreenToolbarVisible)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter PowerShellAppTitleBarTests`

Expected: FAIL with a compiler error similar to `type 'WindowChromeConfiguration' has no member 'fullscreenToolbarVisible'`

- [ ] **Step 3: Write the minimal implementation**

```swift
import SwiftUI
import SwiftTerm

enum WindowChromeConfiguration {
    static let navigationTitle: String? = nil
    static let toolbarTitle = "PowerShell"
    static let fullscreenToolbarVisible = true

    @MainActor
    static let titlePlacement: ToolbarItemPlacement = .principal
}

@main
struct PowerShellApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var sessionManager = SessionManager()
    @State private var nlViewModel: NLViewModel
    @State private var llmService = LLMService()
    @State private var themeManager = ThemeManager()

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
            .toolbar {
                ToolbarItem(placement: WindowChromeConfiguration.titlePlacement) {
                    Text(WindowChromeConfiguration.toolbarTitle)
                        .font(.headline)
                }
            }
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
                    NSApp.activate(ignoringOtherApps: true)
                }

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
            SettingsView(llmService: llmService, themeManager: themeManager)
        }
    }
}

struct TerminalDetailView: View {
    let session: Session
    @Bindable var nlViewModel: NLViewModel
    let themeManager: ThemeManager
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

            ZStack(alignment: .bottom) {
                TerminalPaneView(
                    shellType: session.shellType,
                    theme: themeManager.currentTheme,
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
}
```

- [ ] **Step 4: Run the focused test to verify it passes**

Run: `swift test --filter PowerShellAppTitleBarTests`

Expected: PASS with `Executed 1 test, with 0 failures`

- [ ] **Step 5: Run the package build**

Run: `swift build`

Expected: PASS

- [ ] **Step 6: Run the full test suite and note the known baseline failure**

Run: `swift test`

Expected:
- `PowerShellAppTitleBarTests` passes
- Existing unrelated baseline failure may still appear in `Tests/PowerShellTests/NLDetectorTests.swift:testEnglishNL`
- No new failures related to toolbar visibility logic

- [ ] **Step 7: Manually verify the toolbar behavior**

Run: `swift run PowerShell`

Expected:
- normal window keeps the toolbar visible
- fullscreen keeps the toolbar visible without requiring hover at the top edge
- `Hide Sidebar` and `PowerShell` remain visible in the same top bar
- terminal input, session switching, and suggestion overlays still behave as before

- [ ] **Step 8: Commit**

```bash
git add Sources/PowerShell/App/PowerShellApp.swift Tests/PowerShellTests/PowerShellAppTitleBarTests.swift
git commit -m "$(cat <<'EOF'
[opt]取消全屏下 toolbar 自动隐藏

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```
