import SwiftUI
import SwiftTerm

/// Terminal view subclass that handles IME composition and attention signal monitoring.
/// All input is passed through directly to the shell — no NL interception.
final class InterceptingTerminalView: LocalProcessTerminalView {
    var onAttentionNeeded: ((AttentionType) -> Void)?
    var onTerminalFocused: (() -> Void)?

    private let outputMonitor = OutputMonitor()

    // IME composition state
    private var markedText = ""
    private var markedDisplayWidth = 0

    /// Send text directly to the child process.
    func sendDirect(_ txt: String) {
        send(txt: txt)
    }

    // MARK: - Track committed text via insertText

    public override func insertText(_ string: Any, replacementRange: NSRange) {
        eraseMarkedText()
        outputMonitor.reset()
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

        guard !newText.isEmpty else { return }

        markedText = newText
        let width = displayWidth(of: newText)
        guard canRenderMarkedText(width: width) else {
            markedDisplayWidth = 0
            return
        }

        feed(text: "\u{1b}[\(width)@")
        feed(text: newText)
        markedDisplayWidth = width
    }

    public override func hasMarkedText() -> Bool {
        return !markedText.isEmpty
    }

    public override func markedRange() -> NSRange {
        if markedText.isEmpty {
            return NSRange(location: NSNotFound, length: 0)
        }
        return NSRange(location: 0, length: markedText.utf16.count)
    }

    public override func unmarkText() {
        eraseMarkedText()
    }

    public override func validAttributesForMarkedText() -> [NSAttributedString.Key] {
        return [.underlineStyle, .foregroundColor, .backgroundColor]
    }

    private func eraseMarkedText() {
        if markedDisplayWidth > 0 {
            feed(text: "\u{1b}[\(markedDisplayWidth)D\u{1b}[\(markedDisplayWidth)P")
        }
        markedText = ""
        markedDisplayWidth = 0
    }

    private func canRenderMarkedText(width: Int) -> Bool {
        let cursor = terminal.getCursorLocation()
        if cursor.x + width <= terminal.cols {
            return true
        }
        let endRow = min(terminal.rows - 1, cursor.y + ((width - 1) / terminal.cols))
        guard cursor.y < endRow else { return false }
        for row in (cursor.y + 1)...endRow {
            guard let line = terminal.getLine(row: row), !line.hasAnyContent() else {
                return false
            }
        }
        return true
    }

    private func displayWidth(of string: String) -> Int {
        var width = 0
        for scalar in string.unicodeScalars {
            width += isEastAsianWide(scalar) ? 2 : 1
        }
        return width
    }

    private func isEastAsianWide(_ scalar: Unicode.Scalar) -> Bool {
        let v = scalar.value
        if (0x4E00...0x9FFF).contains(v) { return true }
        if (0x3400...0x4DBF).contains(v) { return true }
        if (0x20000...0x2A6DF).contains(v) { return true }
        if (0x2A700...0x2CEAF).contains(v) { return true }
        if (0xF900...0xFAFF).contains(v) { return true }
        if (0x2F800...0x2FA1F).contains(v) { return true }
        if (0x3040...0x309F).contains(v) { return true }
        if (0x30A0...0x30FF).contains(v) { return true }
        if (0xAC00...0xD7AF).contains(v) { return true }
        if (0x1100...0x11FF).contains(v) { return true }
        if (0xFF01...0xFF60).contains(v) { return true }
        if (0xFFE0...0xFFE6).contains(v) { return true }
        if (0x3000...0x33FF).contains(v) { return true }
        if (0xFE30...0xFE6F).contains(v) { return true }
        if (0x2E80...0x2FDF).contains(v) { return true }
        return false
    }

    // MARK: - Monitor output for attention signals

    public override func dataReceived(slice: ArraySlice<UInt8>) {
        // Erase inline composition BEFORE super moves the cursor (position is correct here).
        // After processing, re-render at the new cursor position so the composition
        // "follows" the output instead of disappearing or corrupting the display.
        let savedText = markedDisplayWidth > 0 ? markedText : ""
        if markedDisplayWidth > 0 {
            feed(text: "\u{1b}[\(markedDisplayWidth)D\u{1b}[\(markedDisplayWidth)P")
            markedDisplayWidth = 0
        }
        super.dataReceived(slice: slice)
        outputMonitor.processOutput(slice: slice)
        if !savedText.isEmpty {
            let width = displayWidth(of: savedText)
            if canRenderMarkedText(width: width) {
                feed(text: "\u{1b}[\(width)@")
                feed(text: savedText)
                markedDisplayWidth = width
            }
        }
    }

    func setupOutputMonitor() {
        outputMonitor.onAttentionNeeded = { [weak self] type in
            self?.onAttentionNeeded?(type)
        }
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
        DebugLog.write("[TerminalPane] startProcess: sessionId=\(sessionId.uuidString), POWERSHELL_SESSION_ID injected")
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
