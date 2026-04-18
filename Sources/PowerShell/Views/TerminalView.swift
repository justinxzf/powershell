import SwiftUI
import SwiftTerm

/// Terminal view subclass that intercepts text input to detect natural language.
/// Text is tracked via `insertText` override (which properly handles IME composition),
/// while control keys (Enter, Backspace, Ctrl+U/C) are handled in `send(source:data:)`.
/// NL input is intercepted (line cleared with Ctrl+U) and forwarded to the LLM.
/// When history navigation (Up/Down) is used, NL detection is skipped since we
/// can't accurately track the shell-populated history content.
final class InterceptingTerminalView: LocalProcessTerminalView {
    var onLineEntered: ((String) -> Void)?
    var onSuggestionAction: ((SuggestionAction) -> Void)?
    var onAttentionNeeded: ((AttentionType) -> Void)?
    var onTerminalFocused: (() -> Void)?
    var hasActiveSuggestion = false
    var skipNLDetection = false

    private var inputBuffer = ""
    private var isSendingDirectly = false
    private var bufferReliable = true
    private let outputMonitor = OutputMonitor()

    enum SuggestionAction {
        case confirm
        case cancel
    }

    /// Send text directly to the child process, bypassing NL interception.
    func sendDirect(_ txt: String) {
        isSendingDirectly = true
        send(txt: txt)
        isSendingDirectly = false
    }

    // MARK: - Track text via insertText (handles IME properly)

    public override func insertText(_ string: Any, replacementRange: NSRange) {
        if !isSendingDirectly && !hasActiveSuggestion {
            if let str = string as? String {
                inputBuffer += str
            } else if let nsStr = string as? NSString {
                inputBuffer += nsStr as String
            }
            outputMonitor.reset()
        }
        super.insertText(string, replacementRange: replacementRange)
    }

    // MARK: - Monitor output for attention signals

    public override func dataReceived(slice: ArraySlice<UInt8>) {
        super.dataReceived(slice: slice)
        outputMonitor.processOutput(slice: slice)
    }

    func setupOutputMonitor() {
        outputMonitor.onAttentionNeeded = { [weak self] type in
            self?.onAttentionNeeded?(type)
        }
    }

    // MARK: - Handle control keys in send(source:data:)

    public override func send(source: TerminalView, data: ArraySlice<UInt8>) {
        if isSendingDirectly {
            super.send(source: source, data: data)
            return
        }

        let bytes = Array(data)

        // Up/Down arrow — history navigation makes buffer unreliable
        if isHistoryNavigation(bytes) {
            bufferReliable = false
            inputBuffer = ""
            super.send(source: source, data: data)
            return
        }

        // Enter key (CR or LF)
        if bytes == [13] || bytes == [10] {
            if hasActiveSuggestion {
                hasActiveSuggestion = false
                onSuggestionAction?(.confirm)
                return
            }

            let reliable = bufferReliable
            bufferReliable = true
            let line = inputBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
            inputBuffer = ""

            // When Claude Code is active, pass all input directly
            if skipNLDetection {
                super.send(source: source, data: data)
                return
            }

            // Only do NL detection if buffer is reliable (no history navigation)
            if reliable && !line.isEmpty {
                let inputType = NLDetector.detect(line)
                if inputType == .naturalLanguage {
                    super.send(source: source, data: ArraySlice([0x15]))
                    onLineEntered?(line)
                    return
                }
            }

            super.send(source: source, data: data)
            return
        }

        // Escape key alone
        if bytes == [0x1b] {
            if hasActiveSuggestion {
                hasActiveSuggestion = false
                onSuggestionAction?(.cancel)
                return
            }
            super.send(source: source, data: data)
            return
        }

        // Any other key while suggestion is active → cancel suggestion
        if hasActiveSuggestion {
            hasActiveSuggestion = false
            onSuggestionAction?(.cancel)
        }

        // Backspace — remove last character from buffer
        if bytes == [0x7f] || bytes == [0x08] {
            if !inputBuffer.isEmpty { inputBuffer.removeLast() }
            super.send(source: source, data: data)
            return
        }

        // Ctrl+U (clear line) or Ctrl+C (interrupt) — reset everything
        if bytes == [0x15] || bytes == [0x03] {
            inputBuffer = ""
            bufferReliable = true
            super.send(source: source, data: data)
            return
        }

        // All other data (escape sequences for left/right, etc.)
        super.send(source: source, data: data)
    }

    // MARK: - History navigation detection

    private func isHistoryNavigation(_ bytes: [UInt8]) -> Bool {
        // Up:    ESC [ A  or  ESC O A
        // Down:  ESC [ B  or  ESC O B
        if bytes.count == 3 && bytes[0] == 0x1b {
            if bytes[1] == 0x5b && (bytes[2] == 0x41 || bytes[2] == 0x42) { return true }
            if bytes[1] == 0x4f && (bytes[2] == 0x41 || bytes[2] == 0x42) { return true }
        }
        return false
    }
}

// MARK: - TerminalPaneView

struct TerminalPaneView: NSViewRepresentable {
    let shellType: ShellType
    let theme: TerminalTheme
    let onTitleChanged: (@Sendable (String) -> Void)?
    let onDirectoryChanged: (@Sendable (String?) -> Void)?
    let onProcessTerminated: (@Sendable (Int32?) -> Void)?
    let onTerminalCreated: (@Sendable (InterceptingTerminalView) -> Void)?
    let onFocus: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> TerminalHostView {
        let terminal = InterceptingTerminalView(frame: .zero)
        terminal.processDelegate = context.coordinator
        terminal.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        terminal.nativeBackgroundColor = theme.nsBackgroundColor
        terminal.nativeForegroundColor = theme.nsForegroundColor
        terminal.installColors(theme.swiftTermAnsiColors)
        terminal.startProcess(executable: shellType.launchPath)

        let hostView = TerminalHostView(terminalView: terminal)
        context.coordinator.hostView = hostView

        onTerminalCreated?(terminal)
        terminal.onTerminalFocused = { [weak terminal] in
            guard terminal != nil else { return }
            DispatchQueue.main.async {
                onFocus?()
            }
        }

        return hostView
    }

    func updateNSView(_ nsView: TerminalHostView, context: Context) {
        let terminal = nsView.terminalView
        guard context.coordinator.lastAppliedThemeId != theme.id else { return }
        context.coordinator.lastAppliedThemeId = theme.id
        terminal.nativeBackgroundColor = theme.nsBackgroundColor
        terminal.nativeForegroundColor = theme.nsForegroundColor
        terminal.installColors(theme.swiftTermAnsiColors)
    }

    final class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
        private let onTitleChanged: (@Sendable (String) -> Void)?
        private let onDirectoryChanged: (@Sendable (String?) -> Void)?
        private let onProcessTerminated: (@Sendable (Int32?) -> Void)?
        weak var hostView: TerminalHostView?
        var lastAppliedThemeId: String?

        init(parent: TerminalPaneView) {
            self.onTitleChanged = parent.onTitleChanged
            self.onDirectoryChanged = parent.onDirectoryChanged
            self.onProcessTerminated = parent.onProcessTerminated
        }

        func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

        func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
            DispatchQueue.main.async { [onTitleChanged] in
                onTitleChanged?(title)
            }
        }

        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
            DispatchQueue.main.async { [onDirectoryChanged] in
                onDirectoryChanged?(directory)
            }
        }

        func processTerminated(source: TerminalView, exitCode: Int32?) {
            DispatchQueue.main.async { [onProcessTerminated] in
                onProcessTerminated?(exitCode)
            }
        }
    }
}

// MARK: - TerminalHostView

/// NSView host that wraps InterceptingTerminalView and properly handles
/// the responder chain so keyboard events reach the terminal.
final class TerminalHostView: NSView {
    let terminalView: InterceptingTerminalView

    init(terminalView: InterceptingTerminalView) {
        self.terminalView = terminalView
        super.init(frame: .zero)
        wantsLayer = true

        addSubview(terminalView)
        terminalView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            terminalView.leadingAnchor.constraint(equalTo: leadingAnchor),
            terminalView.trailingAnchor.constraint(equalTo: trailingAnchor),
            terminalView.topAnchor.constraint(equalTo: topAnchor),
            terminalView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        let result = window?.makeFirstResponder(terminalView) ?? false
        if result {
            terminalView.onTerminalFocused?()
        }
        return result
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            DispatchQueue.main.async { [weak self] in
                guard let self, let window = self.window else { return }
                NSApp.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)
                window.makeFirstResponder(self.terminalView)
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(terminalView)
    }
}
