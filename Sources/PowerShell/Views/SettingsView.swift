import SwiftUI

struct SettingsView: View {
    @State private var selectedThemeId: String
    @State private var fontSizeRaw: String
    @State private var showSaved = false
    var themeManager: ThemeManager

    init(themeManager: ThemeManager) {
        self.themeManager = themeManager
        _selectedThemeId = State(initialValue: UserDefaults.standard.string(forKey: "terminal_theme") ?? TerminalTheme.defaultTheme.id)
        _fontSizeRaw = State(initialValue: UserDefaults.standard.string(forKey: "terminal_font_size") ?? FontSize.medium.rawValue)
    }

    private var hasChanges: Bool {
        let savedTheme = UserDefaults.standard.string(forKey: "terminal_theme") ?? TerminalTheme.defaultTheme.id
        let savedFont = UserDefaults.standard.string(forKey: "terminal_font_size") ?? FontSize.medium.rawValue
        return selectedThemeId != savedTheme || fontSizeRaw != savedFont
    }

    var body: some View {
        Form {
            Section("外观") {
                Picker("字体大小", selection: $fontSizeRaw) {
                    ForEach(FontSize.allCases, id: \.self) { size in
                        Text(size.displayName).tag(size.rawValue)
                    }
                }

                Picker("主题", selection: $selectedThemeId) {
                    ForEach(TerminalTheme.allThemes) { theme in
                        Text(theme.displayName).tag(theme.id)
                    }
                }
            }

            Section("Claude Code 集成") {
                Toggle("自动配置 Hook 通知", isOn: Binding(
                    get: { HookConfigurator.shared.isAutoConfigEnabled },
                    set: { HookConfigurator.shared.setAutoConfigEnabled($0) }
                ))
                HStack(spacing: 4) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                    Text("自动配置 Claude Code Hook，接收任务完成、权限请求等通知")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                HStack {
                    if showSaved {
                        Label("已保存", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .transition(.opacity)
                    }
                    Spacer()
                    Button("保存") {
                        saveSettings()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!hasChanges)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 450, height: 320)
        .animation(.easeInOut(duration: 0.3), value: showSaved)
    }

    private func saveSettings() {
        UserDefaults.standard.set(fontSizeRaw, forKey: "terminal_font_size")
        UserDefaults.standard.set(selectedThemeId, forKey: "terminal_theme")

        if let theme = TerminalTheme.allThemes.first(where: { $0.id == selectedThemeId }) {
            themeManager.currentTheme = theme
        }

        showSaved = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            showSaved = false
        }
    }
}
