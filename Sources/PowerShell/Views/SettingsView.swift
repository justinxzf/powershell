import SwiftUI

enum APIConfigMode: String, CaseIterable {
    case `default` = "default"
    case custom = "custom"

    var displayName: String {
        switch self {
        case .default: return "默认配置"
        case .custom: return "自定义配置"
        }
    }
}

struct SettingsView: View {
    @AppStorage("llm_config_mode") private var configModeRaw = APIConfigMode.default.rawValue
    @AppStorage("llm_provider_type") private var providerTypeRaw = LLMProviderType.openAI.rawValue
    @AppStorage("llm_model") private var model = ""
    @AppStorage("llm_base_url") private var baseURL = ""
    @AppStorage("terminal_theme") private var selectedThemeId = TerminalTheme.defaultTheme.id
    @State private var apiKey = ""
    @State private var showAPIKey = false
    @State private var saveMessage: String?
    var llmService: LLMService
    var themeManager: ThemeManager

    private var configMode: APIConfigMode {
        APIConfigMode(rawValue: configModeRaw) ?? .default
    }

    var body: some View {
        Form {
            Section("API 配置模式") {
                Picker("配置模式", selection: $configModeRaw) {
                    ForEach(APIConfigMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.radioGroup)

                if configMode == .default {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.shield.fill")
                            .foregroundStyle(.green)
                        Text("使用内置 DeepSeek 配置，无需手动设置")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if configMode == .custom {
                Section("LLM 提供商") {
                    Picker("提供商", selection: $providerTypeRaw) {
                        ForEach(LLMProviderType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type.rawValue)
                        }
                    }
                    .onChange(of: providerTypeRaw) { _, _ in
                        model = providerType.defaultModel
                        baseURL = providerType.defaultBaseURL
                        apiKey = (try? KeychainService.load(key: providerType.keychainKey)) ?? ""
                    }
                }

                Section("API 配置") {
                    HStack {
                        if showAPIKey {
                            TextField("API Key", text: $apiKey)
                        } else {
                            SecureField("API Key", text: $apiKey)
                        }
                        Button(showAPIKey ? "隐藏" : "显示") {
                            showAPIKey.toggle()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    TextField("模型", text: $model)
                    TextField("Base URL", text: $baseURL)
                }
            }

            Section("外观") {
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

            Section {
                Button("保存配置") {
                    saveConfig()
                }
                .buttonStyle(.borderedProminent)

                if let message = saveMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(message.hasPrefix("保存失败") ? .red : .green)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 450, height: configMode == .custom ? 530 : 370)
        .onAppear {
            loadConfig()
        }
        .onChange(of: configModeRaw) { _, _ in
            saveConfig()
        }
    }

    private var providerType: LLMProviderType {
        LLMProviderType(rawValue: providerTypeRaw) ?? .openAI
    }

    private func loadConfig() {
        if model.isEmpty {
            model = UserDefaults.standard.string(forKey: "llm_model") ?? providerType.defaultModel
        }
        if baseURL.isEmpty {
            baseURL = UserDefaults.standard.string(forKey: "llm_base_url") ?? providerType.defaultBaseURL
        }
        apiKey = (try? KeychainService.load(key: providerType.keychainKey)) ?? ""
    }

    private func saveConfig() {
        do {
            if configMode == .default {
                // Use built-in DeepSeek config
                let defaultProvider = llmService.createProvider(
                    type: .openAI,
                    apiKey: "sk-369c3ce543bf4751b6a5c505179249b6",
                    model: "deepseek-chat",
                    baseURL: "https://api.deepseek.com/v1/chat/completions"
                )
                llmService.registerProvider(.openAI, provider: defaultProvider)
            } else {
                try KeychainService.save(key: providerType.keychainKey, value: apiKey)
                let provider = llmService.createProvider(
                    type: providerType,
                    apiKey: apiKey,
                    model: model,
                    baseURL: baseURL
                )
                llmService.registerProvider(providerType, provider: provider)
            }

            saveMessage = "配置已保存并生效"
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                saveMessage = nil
            }
        } catch {
            saveMessage = "保存失败: \(error.localizedDescription)"
        }
    }
}
