# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

- **Build**: `swift build`
- **Test**: `swift test`
- **Run**: `swift run PowerShell` (requires macOS GUI session)
- **Platform**: macOS 14.0+, Swift 6.0, SPM
- **Dependency**: SwiftTerm 1.13.0 (sole external dep)

## Architecture

A macOS terminal emulator (SwiftUI + SwiftTerm) that intercepts natural language input, converts it to shell commands via cloud LLM, and presents for confirmation.

### Data Flow

```
User types → InterceptingTerminalView (insertText + send override)
  → NLDetector.detect() on Enter (local rules, no LLM)
    → .command: pass through to shell
    → .naturalLanguage: Ctrl+U to clear line, call LLM
      → CommandSuggestionView overlay (confirm/edit/cancel/execute-original)
        → Confirm → send suggested command to terminal
        → Execute Original → send original input as-is to terminal
```

### Key Files & Roles

- `App/PowerShellApp.swift` — @main, NavigationSplitView, TerminalDetailView (assembles all pieces), TerminalReference (SwiftUI↔AppKit bridge)
- `Views/TerminalView.swift` — **InterceptingTerminalView**: subclasses SwiftTerm's `LocalProcessTerminalView`, overrides `insertText` (tracks input, handles IME) and `send(source:data:)` (intercepts Enter/Escape/Backspace/arrow keys, triggers NL detection). Also contains TerminalPaneView (NSViewRepresentable) and TerminalHostView (responder chain)
- `ViewModels/NLViewModel.swift` — NL detection + LLM conversion + suggestion state machine
- `Services/NLDetector.swift` — Local rule-based classifier. Priority: shell syntax → known command → flag → Chinese chars → NL patterns → default command
- `Services/LLMService.swift` — Provider registry; `LLMProviding` protocol has single method `convert(naturalLanguage:context:)`
- `Services/AnthropicProvider.swift` / `OpenAIProvider.swift` — HTTP clients with identical system prompts; OpenAIProvider reused for DeepSeek

### Non-Obvious Patterns

- **Ctrl+U (0x15) protocol**: When NL detected, sends byte 0x15 to shell to clear line before showing overlay. Same byte typed by user resets `inputBuffer` and `bufferReliable`.
- **History navigation disables NL detection**: Up/Down arrow sets `bufferReliable=false` — shell populates history content that the app can't track, so Enter skips NL check and executes directly.
- **Suggestion Enter interception**: When `hasActiveSuggestion=true`, Enter confirms the suggestion instead of going to the shell. Flag set after LLM response, cleared on confirm/cancel.
- **Session independence**: All sessions live simultaneously in a ZStack with opacity toggling. Each owns its own InterceptingTerminalView + PTY process.
- **Shared LLMService**: One instance shared between NLViewModel (conversion) and SettingsView (config). Settings changes take effect immediately via `registerProvider()`.
- **API keys**: Keychain (service `com.powershell.app`); other config in UserDefaults.
- **UI language is Chinese** — all user-facing strings are 中文.
- **Edit suggestion is incomplete**: `handleEditSuggestion()` returns the suggested command but doesn't place it in the terminal input — just cancels.
