import SwiftUI
import SwiftTerm

struct TerminalPaneView: NSViewRepresentable {
    let shellType: ShellType
    let onTitleChanged: (@Sendable (String) -> Void)?
    let onDirectoryChanged: (@Sendable (String?) -> Void)?
    let onProcessTerminated: (@Sendable (Int32?) -> Void)?
    let onTerminalCreated: (@Sendable (LocalProcessTerminalView) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> TerminalHostView {
        let terminal = LocalProcessTerminalView(frame: .zero)
        terminal.processDelegate = context.coordinator
        terminal.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        terminal.nativeBackgroundColor = NSColor(red: 0.12, green: 0.12, blue: 0.12, alpha: 1)
        terminal.nativeForegroundColor = NSColor(red: 0.8, green: 0.8, blue: 0.8, alpha: 1)
        terminal.startProcess(executable: shellType.launchPath)

        let hostView = TerminalHostView(terminalView: terminal)
        context.coordinator.hostView = hostView

        // Notify the SwiftUI layer about the terminal reference
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

/// NSView host that wraps LocalProcessTerminalView and properly handles
/// the responder chain so keyboard events reach the terminal.
final class TerminalHostView: NSView {
    let terminalView: LocalProcessTerminalView

    init(terminalView: LocalProcessTerminalView) {
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
