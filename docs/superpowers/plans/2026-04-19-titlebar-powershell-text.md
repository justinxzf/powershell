# Title Bar PowerShell Text Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move the fixed `PowerShell` title text from the default macOS navigation title position into the toolbar row beside `Hide Sidebar`.

**Architecture:** Keep the change local to the app scene in `PowerShellApp.swift`. Add a tiny testable `WindowChromeConfiguration` seam that expresses “no navigation title + fixed toolbar title in principal placement”, then wire that configuration into the existing `NavigationSplitView` toolbar without changing fullscreen hover behavior.

**Tech Stack:** Swift 6, SwiftUI, XCTest, macOS 14, Swift Package Manager

---

## File Structure

- Modify: `Sources/PowerShell/App/PowerShellApp.swift` — define the small window-chrome configuration, remove `.navigationTitle("PowerShell")`, and add a `.toolbar` principal item showing `Text("PowerShell")`
- Create: `Tests/PowerShellTests/PowerShellAppTitleBarTests.swift` — verify the window-chrome configuration uses a fixed toolbar title and disables the default navigation title

This plan intentionally keeps the change in one production file. The extra test file exists only to give the UI decision a small, stable seam that can be verified with XCTest before manual UI validation.

---

### Task 1: Move the title text into the toolbar row

**Files:**
- Modify: `Sources/PowerShell/App/PowerShellApp.swift:4-76`
- Test: `Tests/PowerShellTests/PowerShellAppTitleBarTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import PowerShell

final class PowerShellAppTitleBarTests: XCTestCase {
    func testWindowChromeUsesFixedToolbarTitleInsteadOfNavigationTitle() {
        let chrome = WindowChromeConfiguration.main

        XCTAssertNil(chrome.navigationTitle)
        XCTAssertEqual(chrome.toolbarTitle, "PowerShell")
        XCTAssertEqual(chrome.titlePlacement, .principal)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter PowerShellAppTitleBarTests`

Expected: FAIL with a compiler error similar to `cannot find 'WindowChromeConfiguration' in scope`

- [ ] **Step 3: Write the minimal implementation**

```swift
import SwiftUI
import SwiftTerm

struct WindowChromeConfiguration {
    enum TitlePlacement: Equatable {
        case principal
    }

    let navigationTitle: String?
    let toolbarTitle: String
    let titlePlacement: TitlePlacement

    static let main = WindowChromeConfiguration(
        navigationTitle: nil,
        toolbarTitle: "PowerShell",
        titlePlacement: .principal
    )
}

@main
struct PowerShellApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var sessionManager = SessionManager()
    @State private var nlViewModel: NLViewModel
    @State private var llmService = LLMService()
    @State private var themeManager = ThemeManager()

    private let windowChrome = WindowChromeConfiguration.main

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
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(windowChrome.toolbarTitle)
                        .font(.headline)
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter PowerShellAppTitleBarTests`

Expected: PASS with `Executed 1 test, with 0 failures`

- [ ] **Step 5: Run the package test suite**

Run: `swift test`

Expected: PASS with all existing tests green, including the new title-bar test

- [ ] **Step 6: Build and manually verify the UI**

Run: `swift build && swift run PowerShell`

Expected:
- build succeeds
- the default title position no longer shows `PowerShell`
- the toolbar row beside `Hide Sidebar` shows `PowerShell`
- fullscreen still hides/shows the toolbar title together with the toolbar

- [ ] **Step 7: Commit**

```bash
git add Sources/PowerShell/App/PowerShellApp.swift Tests/PowerShellTests/PowerShellAppTitleBarTests.swift
git commit -m "$(cat <<'EOF'
[feat]调整标题栏 PowerShell 文本位置

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```
