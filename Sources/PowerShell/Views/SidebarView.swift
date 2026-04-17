import SwiftUI

@available(macOS 14.0, *)
struct SidebarView: View {
    @Bindable var sessionManager: SessionManager

    var body: some View {
        List(selection: $sessionManager.activeSessionId) {
            ForEach(sessionManager.sessions) { session in
                SidebarItemRow(
                    session: session,
                    isSelected: session.id == sessionManager.activeSessionId,
                    onRename: { newName in
                        sessionManager.rename(sessionId: session.id, newName: newName)
                    }
                )
                .tag(session.id)
                .contextMenu {
                    Button("重命名") {
                        sessionManager.startRenaming(sessionId: session.id)
                    }
                    Divider()
                    Button("关闭", role: .destructive) {
                        sessionManager.delete(sessionId: session.id)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .overlay(alignment: .bottom) {
            HStack {
                Menu {
                    Button("bash") {
                        _ = sessionManager.createSession(shellType: .bash)
                    }
                    Button("zsh") {
                        _ = sessionManager.createSession(shellType: .zsh)
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.title3)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)

                Spacer()
            }
            .padding(8)
            .background(.bar)
        }
    }
}

struct SidebarItemRow: View {
    let session: Session
    let isSelected: Bool
    let onRename: (String) -> Void

    @State private var isEditing = false
    @State private var editName = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(session.isActive ? Color.green : Color.gray.opacity(0.5))
                .frame(width: 8, height: 8)

            if isEditing {
                TextField("名称", text: $editName)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .focused($isFocused)
                    .onSubmit {
                        let trimmed = editName.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            onRename(trimmed)
                        }
                        isEditing = false
                    }
                    .onChange(of: isFocused) { _, focused in
                        if !focused && isEditing {
                            let trimmed = editName.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !trimmed.isEmpty {
                                onRename(trimmed)
                            }
                            isEditing = false
                        }
                    }
            } else {
                Text(session.name)
                    .lineLimit(1)
            }

            Spacer()
            Text(session.shellType.displayName)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .onChange(of: session.needsRename) { _, needsRename in
            if needsRename {
                editName = session.name
                isEditing = true
                isFocused = true
            }
        }
    }
}
