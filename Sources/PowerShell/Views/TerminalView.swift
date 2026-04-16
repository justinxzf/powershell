import SwiftUI
import SwiftTerm

/// Terminal view subclass that intercepts the `send(source:data:)` delegate method
/// to detect natural language input. Commands pass through normally; NL input is
/// intercepted (line cleared with Ctrl+U) and forwarded to the LLM via `onLineEntered`.
final class InterceptingTerminalView: LocalProcessTerminalView {
    var onLineEntered: ((String) -> Void)?
    var onSuggestionAction: ((SuggestionAction) -> Void)?
    var hasActiveSuggestion = false

    private var inputBuffer = ""
    private var isSendingDirectly = false

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

    // MARK: - Intercept data before it reaches the shell process

    public override func send(source: TerminalView, data: ArraySlice<UInt8>) {
        if isSendingDirectly {
            super.send(source: source, data: data)
            return
        }

        let bytes = Array(data)

        // Enter key (CR or LF)
        if bytes == [13] || bytes == [10] {
            if hasActiveSuggestion {
                hasActiveSuggestion = false
                onSuggestionAction?(.confirm)
                return
            }

            let line = inputBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
            inputBuffer = ""

            if !line.isEmpty {
                let inputType = NLDetector.detect(line)
                if inputType == .naturalLanguage {
                    // Clear the shell's current line (Ctrl+U) instead of executing
                    super.send(source: source, data: ArraySlice([0x15]))
                    onLineEntered?(line)
                    return
                }
            }

            super.send(source: source, data: data)
            return
        }

        // Escape key (ESC byte alone)
        if bytes == [0x1b] {
            if hasActiveSuggestion {
                hasActiveSuggestion = false
                onSuggestionAction?(.cancel)
                return
            }
            inputBuffer = ""
            super.send(source: source, data: data)
            return
        }

        // Any other key while suggestion is active → cancel suggestion
        if hasActiveSuggestion {
            hasActiveSuggestion = false
            onSuggestionAction?(.cancel)
        }

        // Backspace
        if bytes == [0x7f] || bytes == [0x08] {
            if !inputBuffer.isEmpty { inputBuffer.removeLast() }
            super.send(source: source, data: data)
            return
        }

        // Ctrl+U (clear line) or Ctrl+C (interrupt)
        if bytes == [0x15] || bytes == [0x03] {
            inputBuffer = ""
            super.send(source: source, data: data)
            return
        }

        // Escape sequences (arrow keys, etc.) — can't track complex editing
        if bytes.first == 0x1b {
            inputBuffer = ""
            super.send(source: source, data: data)
            return
        }

        // Regular printable text (ASCII + UTF-8 including CJK)
        if let text = String(bytes: bytes, encoding: .utf8), !text.isEmpty {
            inputBuffer += text
            super.send(source: source, data: data)
            return
        }

        // Unknown data — reset buffer and pass through
        inputBuffer = ""
        super.send(source: source, data: data)
    }
}

// MARK: - TerminalPaneView

struct TerminalPaneView: NSViewRepresentable {
    let shellType: ShellType
    let onTitleChanged: (@Sendable (String) -> Void)?
    let onDirectoryChanged: (@Sendable (String?) -> Void)?
    let onProcessTerminated: (@Sendable (Int32?) -> Void)?
    let onTerminalCreated: (@Sendable (InterceptingTerminalView) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> TerminalHostView {
        let terminal = InterceptingTerminalView(frame: .zero)
        terminal.processDelegate = context.coordinator
        terminal.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        terminal.nativeBackgroundColor = NSColor(red: 0.12, green: 0.12, blue: 0.12, alpha: 1)
        terminal.nativeForegroundColor = NSColor(red: 0.8, green: 0.8, blue: 0.8, alpha: 1)
        terminal.startProcess(executable: shellType.launchPath)

        let hostView = TerminalHostView(terminalView: terminal)
        context.coordinator.hostView = hostView

        onTerminalCreated?(terminal)

        return hostView
    }

    func updateNSView(_ nsView: TerminalHostView, context: Context) {}

    final class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
        private let onTitleChanged: (@Sendable (String) -> Void)?
        private let onDirectoryChanged: (@Sendable (String?) -> Void)?
        private let onProcessTerminated: (@Sendable (Int32?) -> Void)?
        weak var hostView: TerminalHostView?

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
        window?.makeFirstResponder(terminalView) ?? false
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
