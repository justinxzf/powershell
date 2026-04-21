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

    // IME composition state
    private var markedText = ""
    private var markedDisplayWidth = 0

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
        eraseMarkedText()
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

    // MARK: - IME composition (setMarkedText / hasMarkedText / unmarkText)

    public override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        let newText: String
        if let str = string as? String {
            newText = str
        } else if let attrStr = string as? NSAttributedString {
            newText = attrStr.string
        } else {
            newText = ""
        }

        eraseMarkedText()

        if !newText.isEmpty {
            feed(text: newText)
            markedText = newText
            markedDisplayWidth = displayWidth(of: newText)
        }
    }

    public override func hasMarkedText() -> Bool {
        return !markedText.isEmpty
    }

    public override func markedRange() -> NSRange {
        if markedText.isEmpty {
            return NSRange(location: NSNotFound, length: 0)
        }
        return NSRange(location: 0, length: markedText.count)
    }

    public override func unmarkText() {
        eraseMarkedText()
    }

    public override func validAttributesForMarkedText() -> [NSAttributedString.Key] {
        return [.underlineStyle, .foregroundColor, .backgroundColor]
    }

    private func eraseMarkedText() {
        guard markedDisplayWidth > 0 else { return }
        // Move cursor left by display width, then clear to end of line
        feed(text: "\u{1b}[\(markedDisplayWidth)D\u{1b}[K")
        markedText = ""
        markedDisplayWidth = 0
    }

    private func displayWidth(of string: String) -> Int {
        var width = 0
        for scalar in string.unicodeScalars {
            if isEastAsianWide(scalar) {
                width += 2
            } else {
                width += 1
            }
        }
        return width
    }

    private func isEastAsianWide(_ scalar: Unicode.Scalar) -> Bool {
        let v = scalar.value
        // CJK Unified Ideographs
        if (0x4E00...0x9FFF).contains(v) { return true }
        // CJK Extensions A-D
        if (0x3400...0x4DBF).contains(v) { return true }
        // CJK Extensions B-F
        if (0x20000...0x2A6DF).contains(v) { return true }
        if (0x2A700...0x2CEAF).contains(v) { return true }
        // CJK Compatibility
        if (0xF900...0xFAFF).contains(v) { return true }
        if (0x2F800...0x2FA1F).contains(v) { return true }
        // Hiragana, Katakana
        if (0x3040...0x309F).contains(v) { return true }
        if (0x30A0...0x30FF).contains(v) { return true }
        // Hangul
        if (0xAC00...0xD7AF).contains(v) { return true }
        if (0x1100...0x11FF).contains(v) { return true }
        // Fullwidth Forms
        if (0xFF01...0xFF60).contains(v) { return true }
        if (0xFFE0...0xFFE6).contains(v) { return true }
        // CJK Symbols and Punctuation, Bopomofo, etc.
        if (0x3000...0x33FF).contains(v) { return true }
        if (0xFE30...0xFE6F).contains(v) { return true }
        // CJK Radicals / Kangxi
        if (0x2E80...0x2FDF).contains(v) { return true }
        return false
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

            // When NL command is disabled in settings, pass through directly
            let nlEnabled = UserDefaults.standard.object(forKey: "nl_command_enabled") as? Bool ?? false
            if !nlEnabled {
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

// MARK: - FontSize

enum FontSize: String, CaseIterable {
    case small = "small"
    case medium = "medium"
    case large = "large"
    case extraLarge = "extraLarge"

    var displayName: String {
        switch self {
        case .small: return "小"
        case .medium: return "中"
        case .large: return "大"
        case .extraLarge: return "特大"
        }
    }

    var pointSize: CGFloat {
        switch self {
        case .small: return 11
        case .medium: return 13
        case .large: return 16
        case .extraLarge: return 20
        }
    }
}

// MARK: - TerminalPaneView

struct TerminalPaneView: NSViewRepresentable {
    let shellType: ShellType
    let theme: TerminalTheme
    let fontSize: FontSize
    let sessionId: UUID
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
        terminal.changeScrollback(50_000)
        terminal.processDelegate = context.coordinator
        terminal.font = NSFont.monospacedSystemFont(ofSize: fontSize.pointSize, weight: .regular)
        terminal.nativeBackgroundColor = theme.nsBackgroundColor
        terminal.nativeForegroundColor = theme.nsForegroundColor
        terminal.installColors(theme.swiftTermAnsiColors)
        var env = Terminal.getEnvironmentVariables(termName: "xterm-256color")
        env.append("POWERSHELL_SESSION_ID=\(sessionId.uuidString)")
        terminal.startProcess(executable: shellType.launchPath, environment: env, currentDirectory: NSHomeDirectory())

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
        if context.coordinator.lastAppliedThemeId != theme.id {
            context.coordinator.lastAppliedThemeId = theme.id
            terminal.nativeBackgroundColor = theme.nsBackgroundColor
            terminal.nativeForegroundColor = theme.nsForegroundColor
            terminal.installColors(theme.swiftTermAnsiColors)
        }
        if context.coordinator.lastAppliedFontSize != fontSize.pointSize {
            context.coordinator.lastAppliedFontSize = fontSize.pointSize
            terminal.font = NSFont.monospacedSystemFont(ofSize: fontSize.pointSize, weight: .regular)
        }
    }

    final class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
        private let onTitleChanged: (@Sendable (String) -> Void)?
        private let onDirectoryChanged: (@Sendable (String?) -> Void)?
        private let onProcessTerminated: (@Sendable (Int32?) -> Void)?
        weak var hostView: TerminalHostView?
        var lastAppliedThemeId: String?
        var lastAppliedFontSize: CGFloat?

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
