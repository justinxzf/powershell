# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

- **Build**: `swift build`
- **Test**: `swift test` (or `xcodebuild test -scheme PowerShell -destination 'platform=macOS'`)
- **Run**: `swift run PowerShell` (requires macOS GUI session)
- **Platform**: macOS 14.0+, Swift 6.0, SPM
- **Dependency**: SwiftTerm 1.13.0 (sole external dep)

## Architecture

A macOS terminal emulator (SwiftUI + SwiftTerm) serving as a Claude Code host. Provides multi-session management, split-pane layout, and floating notifications for Claude Code hook events. All keyboard input is passed through directly to the shell — no interception or LLM processing.

### Data Flow

```
User types → TerminalHostView (NSView, responder chain)
  → InterceptingTerminalView (LocalProcessTerminalView subclass)
    → IME: setMarkedText / insertText → VT sequences to PTY
    → dataReceived: PTY output → OutputMonitor scans OSC 9
      → onAttentionNeeded → NotificationManager → FloatingNotificationPanel

Claude Code hook events:
  claude triggers hook → ~/.powershell/hooks/powershell-hook.sh
    → injects POWERSHELL_SESSION_ID → HTTP POST 127.0.0.1:<port>
      → HookNotificationServer → HookEventRouter
        → coreRoute (SessionStart/End/Notification dispatch)
        → PluginManager.dispatchHookEvent (plugin fan-out)
```

### Key Files & Roles

- `App/PowerShellApp.swift` — @main, NavigationSplitView, TerminalDetailView, TerminalReference (SwiftUI↔AppKit bridge), plugin/service wiring in `.task{}`
- `Views/TerminalView.swift` — **InterceptingTerminalView**: subclasses SwiftTerm's `LocalProcessTerminalView`, handles IME composition, monitors PTY output via OutputMonitor. Also contains TerminalPaneView (NSViewRepresentable) and TerminalHostView (responder chain)
- `ViewModels/SessionManager.swift` — @Observable, manages session lifecycle, split-pane state, Claude Code session mapping, unread counts
- `Services/HookNotificationServer.swift` — TCP server (NWListener, port 9786–9796), receives Claude Code hook events
- `Services/HookConfigurator.swift` — Writes hook script + patches `~/.claude/settings.json`
- `Services/NotificationManager.swift` — Floating notification facade
- `Services/OutputMonitor.swift` — Scans PTY byte stream for OSC 9 escape sequences
- `Services/SkillInstaller.swift` — Copies bundled SKILL.md files to `~/.claude/skills/`
- `Plugins/PowerShellPlugin.swift` — Plugin protocol definition
- `Plugins/PluginManager.swift` — Plugin registry + fan-out dispatch
- `Plugins/HookEventRouter.swift` — Core hook routing + plugin broadcast
- `Plugins/PluginRegistry.swift` — Plugin registration array (the only file plugin authors need to modify)

### Non-Obvious Patterns

- **ZStack opacity toggling**: All sessions live simultaneously in a ZStack. Only the active session (or split pair) has opacity 1 and hit testing enabled. PTY processes are never torn down on switch.
- **POWERSHELL_SESSION_ID env var contract**: Injected at PTY launch, read by hook script, used to correlate Claude Code events to specific terminal panes.
- **Split-pair state memory**: `storedSplitPair` caches the split when navigating away; restored transparently when returning.
- **Hook script versioning**: `HookConfigurator` checks `.script-version` file to avoid unnecessary rewrites.
- **UI language is Chinese** — all user-facing strings are 中文.

## Plugin System

### Development Rules

**When implementing new features, always follow this priority:**

1. **Plugin first**: Evaluate whether the feature can be implemented as a plugin. If yes, implement it as a plugin — do NOT modify core files.
2. **Core only when necessary**: If the feature cannot be implemented as a plugin (e.g., it requires changes to session lifecycle, terminal rendering, or the navigation structure), explain to the user WHY it cannot be a plugin before modifying core files.
3. **Extend plugin capabilities**: If a feature is conceptually a plugin but the current plugin protocol lacks the required hook, prefer extending `PowerShellPlugin` protocol with a new optional method (with default no-op) over bypassing the plugin system.

### Core Files (protected — avoid modifying)

These files form the stable core. Modification requires explicit justification:

- `App/PowerShellApp.swift`
- `ViewModels/SessionManager.swift`
- `Views/TerminalView.swift`
- `Services/HookNotificationServer.swift`
- `Services/NotificationManager.swift`
- `Services/HookConfigurator.swift`
- `Services/SkillInstaller.swift`
- `Services/OutputMonitor.swift`

### Creating a Plugin

1. Create a new file in `Sources/PowerShell/Plugins/`, e.g. `MyPlugin.swift`
2. Conform to `PowerShellPlugin` protocol — implement `pluginId` and `setup()`, override optional hooks as needed
3. Register in `Plugins/PluginRegistry.swift` by adding an instance to the `makePlugins()` array

### Plugin Capabilities

Plugins can:
- Subscribe to Claude Code hook events (`handleHookEvent`)
- React to terminal lifecycle events (`terminalCreated`, `directoryChanged`, `processTerminated`, `terminalFocused`)
- Contribute Settings UI sections (`settingsSection`)
- Bundle and auto-install Claude Code skills (`skillsDirectoryPath`)
