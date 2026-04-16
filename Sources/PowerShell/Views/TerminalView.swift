import SwiftUI
import SwiftTerm

struct TerminalPaneView: NSViewRepresentable {
    let shellType: ShellType
    let onTitleChanged: (@Sendable (String) -> Void)?
    let onDirectoryChanged: (@Sendable (String?) -> Void)?
    let onProcessTerminated: (@Sendable (Int32?) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let terminal = LocalProcessTerminalView(frame: .zero)
        terminal.processDelegate = context.coordinator
        terminal.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        terminal.nativeBackgroundColor = NSColor(red: 0.12, green: 0.12, blue: 0.12, alpha: 1)
        terminal.nativeForegroundColor = NSColor(red: 0.8, green: 0.8, blue: 0.8, alpha: 1)
        terminal.startProcess(executable: shellType.launchPath)
        return terminal
    }

    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {}

    final class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
        private let onTitleChanged: (@Sendable (String) -> Void)?
        private let onDirectoryChanged: (@Sendable (String?) -> Void)?
        private let onProcessTerminated: (@Sendable (Int32?) -> Void)?

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
