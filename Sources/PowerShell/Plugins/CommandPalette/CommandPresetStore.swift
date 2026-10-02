import SwiftUI

/// App-wide preset commands, shared by every window's palette and the Settings section.
@Observable
@MainActor
final class CommandPresetStore {
    static let shared = CommandPresetStore()

    private static let defaultsKey = "command_palette_presets"
    static let defaultPresets = ["claude", "claude --continue", "git status", "git pull"]

    private(set) var presets: [String]

    private init() {
        presets = UserDefaults.standard.stringArray(forKey: Self.defaultsKey) ?? Self.defaultPresets
    }

    func add(_ command: String) {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !presets.contains(trimmed) else { return }
        presets.append(trimmed)
        save()
    }

    func remove(_ command: String) {
        presets.removeAll { $0 == command }
        save()
    }

    private func save() {
        UserDefaults.standard.set(presets, forKey: Self.defaultsKey)
    }
}

struct CommandPresetSettingsSection: View {
    @State private var store = CommandPresetStore.shared
    @State private var newCommand = ""

    var body: some View {
        Section("命令面板（⌘H）") {
            ForEach(store.presets, id: \.self) { command in
                HStack {
                    Text(command)
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button {
                        store.remove(command)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("删除")
                }
            }
            HStack {
                TextField("新增预设命令", text: $newCommand)
                    .onSubmit(add)
                Button("添加", action: add)
                    .disabled(newCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            HStack(alignment: .top, spacing: 4) {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                Text("最近命令读取自 ~/.zsh_history 或 ~/.bash_history。zsh 默认在退出时才写入历史，可在 ~/.zshrc 中加入 setopt INC_APPEND_HISTORY 实时记录。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func add() {
        store.add(newCommand)
        newCommand = ""
    }
}
