import SwiftUI

// MARK: - Model

private struct CommandEntry: Identifiable {
    let id = UUID()
    let text: String
    let scrollRow: Int
}

// MARK: - Plugin

@Observable
@MainActor
final class ChatListPlugin: PowerShellPlugin {

    let pluginId = "com.powershell.chatlist"

    fileprivate var commandsBySession: [UUID: [CommandEntry]] = [:]
    fileprivate var terminalsBySession: [UUID: InterceptingTerminalView] = [:]
    var openSessionId: UUID? = nil

    func setup() {
        PluginManager.shared.registerChatListPlugin(self)
    }

    func terminalCreated(_ terminal: InterceptingTerminalView, session: Session) {
        terminalsBySession[session.id] = terminal
        DebugLog.write("[ChatList] terminalCreated sessionId=\(session.id)")
        terminal.onUserCommandEntered = { [weak self] text, row in
            self?.commandsBySession[session.id, default: []].append(
                CommandEntry(text: text, scrollRow: row)
            )
        }
    }

    func sessionWillDelete(sessionId: UUID) {
        commandsBySession.removeValue(forKey: sessionId)
        terminalsBySession.removeValue(forKey: sessionId)
        if openSessionId == sessionId { openSessionId = nil }
    }

    func headerAccessoryView(for session: Session, allSessions: [Session]) -> AnyView? {
        AnyView(ChatListButton(plugin: self, sessionId: session.id))
    }

    func overlayView(size: CGSize) -> AnyView? {
        AnyView(ChatListOverlayContainer(plugin: self, size: size))
    }
}

// MARK: - Overlay Container

/// Always present in the hierarchy; directly observes plugin.openSessionId so
/// SwiftUI's @Observable tracking is guaranteed to work without relying on the
/// parent view re-rendering through function-call chains.
private struct ChatListOverlayContainer: View {
    let plugin: ChatListPlugin
    let size: CGSize

    var body: some View {
        let _ = DebugLog.write("[ChatList] container.body evaluated, openSessionId=\(plugin.openSessionId?.uuidString ?? "nil"), knownSessions=\(plugin.terminalsBySession.keys.map { $0.uuidString.prefix(8) })")
        if let sessionId = plugin.openSessionId,
           let terminal = plugin.terminalsBySession[sessionId] {
            let entries = plugin.commandsBySession[sessionId] ?? []
            let _ = DebugLog.write("[ChatList] showing panel, entries=\(entries.count)")
            ChatListPanel(
                plugin: plugin,
                sessionId: sessionId,
                entries: entries,
                terminal: terminal,
                size: size
            )
        }
    }
}

// MARK: - Header Button

private struct ChatListButton: View {
    let plugin: ChatListPlugin
    let sessionId: UUID

    var body: some View {
        Button {
            let next = plugin.openSessionId == sessionId ? nil : sessionId
            DebugLog.write("[ChatList] button tapped sessionId=\(sessionId), openSessionId: \(plugin.openSessionId?.uuidString ?? "nil") → \(next?.uuidString ?? "nil")")
            plugin.openSessionId = next
        } label: {
            Image(systemName: "sidebar.right")
                .font(.system(size: 13))
                .foregroundStyle(plugin.openSessionId == sessionId ? Color.accentColor : Color.secondary)
        }
        .buttonStyle(.plain)
        .help("历史输入")
    }
}

// MARK: - Panel

private struct ChatListPanel: View {
    let plugin: ChatListPlugin
    let sessionId: UUID
    let entries: [CommandEntry]
    let terminal: InterceptingTerminalView
    let size: CGSize

    private let panelWidth: CGFloat = 260

    var body: some View {
        HStack(spacing: 0) {
            Spacer()
            VStack(spacing: 0) {
                panelHeader
                Divider()
                entryList
            }
            .frame(width: panelWidth)
            .background(.regularMaterial)
            .shadow(color: .black.opacity(0.2), radius: 8, x: -4, y: 0)
        }
        .frame(width: size.width, height: size.height)
    }

    private var panelHeader: some View {
        HStack {
            Text("历史输入")
                .font(.subheadline)
                .fontWeight(.medium)
            Spacer()
            Button {
                plugin.openSessionId = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var entryList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(entries.reversed()) { entry in
                    CommandRow(text: entry.text) {
                        let rows = terminal.terminal.rows
                        let targetRow = max(0, entry.scrollRow - rows / 2)
                        let thumb = Double(terminal.scrollThumbsize)
                        if thumb > 0 && thumb < 1.0 {
                            let maxRow = Int(Double(rows) * (1.0 / thumb - 1.0))
                            if targetRow <= maxRow {
                                terminal.scrollTo(row: targetRow)
                            }
                        }
                        plugin.openSessionId = nil
                    }
                    Divider().padding(.leading, 12)
                }
            }
        }
    }
}

// MARK: - Command Row

private struct CommandRow: View {
    let text: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(String(text.prefix(30)))
                .font(.system(.body, design: .monospaced))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isHovered ? Color.accentColor.opacity(0.15) : Color.clear)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
