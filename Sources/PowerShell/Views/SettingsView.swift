import SwiftUI

struct SettingsView: View {
    @AppStorage("terminal_theme") private var selectedThemeId = TerminalTheme.defaultTheme.id
    @AppStorage("terminal_font_size") private var fontSizeRaw = FontSize.medium.rawValue
    var themeManager: ThemeManager

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
                .onChange(of: selectedThemeId) { _, newId in
                    if let theme = TerminalTheme.allThemes.first(where: { $0.id == newId }) {
                        themeManager.currentTheme = theme
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
        }
        .formStyle(.grouped)
        .frame(width: 450, height: 280)
    }
}
