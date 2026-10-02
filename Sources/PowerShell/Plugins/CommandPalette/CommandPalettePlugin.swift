import SwiftUI

struct PaletteItem: Identifiable, Equatable {
    enum Kind { case preset, history }
    let kind: Kind
    let text: String
    var id: String { "\(kind)-\(text)" }
}

private final class EventMonitorToken {
    nonisolated(unsafe) let monitor: Any
    init(_ monitor: Any) { self.monitor = monitor }
    deinit { NSEvent.removeMonitor(monitor) }
}

// MARK: - Plugin

@Observable
@MainActor
final class CommandPalettePlugin: PowerShellPlugin {

    let pluginId = "com.powershell.commandpalette"

    private(set) var openSessionId: UUID? = nil
    var query = "" {
        didSet { if query != oldValue { selectedIndex = 0 } }
    }
    var selectedIndex = 0
    private(set) var recentCommands: [String] = []

    @ObservationIgnored private var terminals: [UUID: (view: InterceptingTerminalView, shell: ShellType)] = [:]
    @ObservationIgnored private var keyMonitor: EventMonitorToken?
    @ObservationIgnored private let presetStore = CommandPresetStore.shared

    var items: [PaletteItem] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        func matches(_ s: String) -> Bool { q.isEmpty || s.lowercased().contains(q) }
        let presets = presetStore.presets.filter(matches)
        let presetSet = Set(presetStore.presets)
        let history = recentCommands.filter { matches($0) && !presetSet.contains($0) }
        return presets.map { PaletteItem(kind: .preset, text: $0) }
            + history.map { PaletteItem(kind: .history, text: $0) }
    }

    func setup(host: PluginManager) {
        guard keyMonitor == nil,
              let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
                  self?.handleKeyDown(event) ?? event
              }) else { return }
        keyMonitor = EventMonitorToken(monitor)
        CommandPaletteHotKey.shared.add(self)
    }

    func terminalCreated(_ terminal: InterceptingTerminalView, session: Session) {
        terminals[session.id] = (terminal, session.shellType)
    }

    func sessionWillDelete(sessionId: UUID) {
        terminals.removeValue(forKey: sessionId)
        if openSessionId == sessionId { openSessionId = nil }
    }

    func sessionDidActivate(sessionId: UUID) {
        if openSessionId != nil && openSessionId != sessionId { openSessionId = nil }
    }

    func settingsSection() -> (any View)? {
        return CommandPresetSettingsSection()
    }

    func overlayView(size: CGSize) -> AnyView? {
        AnyView(CommandPaletteOverlay(plugin: self, size: size))
    }

    // MARK: - Actions

    func open(sessionId: UUID) {
        guard let shell = terminals[sessionId]?.shell else { return }
        query = ""
        selectedIndex = 0
        recentCommands = []
        openSessionId = sessionId
        Task {
            let commands = await Task.detached { ShellHistoryReader.recentCommands(for: shell) }.value
            guard self.openSessionId == sessionId else { return }
            self.recentCommands = commands
        }
    }

    func close() {
        guard let sessionId = openSessionId else { return }
        openSessionId = nil
        if let terminal = terminals[sessionId]?.view {
            terminal.window?.makeFirstResponder(terminal)
        }
    }

    func commit(_ item: PaletteItem) {
        guard let sessionId = openSessionId, let terminal = terminals[sessionId]?.view else { return }
        close()
        terminal.sendDirect(item.text)
    }

    func moveSelection(by delta: Int) {
        let count = items.count
        guard count > 0 else { return }
        selectedIndex = (selectedIndex + delta + count) % count
    }

    // MARK: - Keyboard

    /// Returns false when ⌘H is not meant for this window's palette, so the app hides as usual.
    func handleHotKey() -> Bool {
        guard let window = NSApp.keyWindow else { return false }
        if openSessionId != nil, ownsOpenPalette(in: window) {
            close()
            return true
        }
        guard let terminal = window.firstResponder as? InterceptingTerminalView,
              let sessionId = terminals.first(where: { $0.value.view === terminal })?.key else {
            return false
        }
        open(sessionId: sessionId)
        return true
    }

    private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        guard openSessionId != nil, ownsOpenPalette(in: event.window) else { return event }
        if let editor = event.window?.firstResponder as? NSTextView, editor.hasMarkedText() {
            return event
        }
        switch event.keyCode {
        case 53: // esc
            close()
        case 125: // down
            moveSelection(by: 1)
        case 126: // up
            moveSelection(by: -1)
        case 36, 76: // return, keypad enter
            let current = items
            guard current.indices.contains(selectedIndex) else { return nil }
            commit(current[selectedIndex])
        default:
            return event
        }
        return nil
    }

    private func ownsOpenPalette(in window: NSWindow?) -> Bool {
        guard let window, let sessionId = openSessionId else { return false }
        return terminals[sessionId]?.view.window === window
    }
}
