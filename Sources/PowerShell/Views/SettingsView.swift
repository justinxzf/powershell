import SwiftUI

struct SettingsView: View {
    @AppStorage("llm_provider_type") private var providerTypeRaw = LLMProviderType.anthropic.rawValue
    @AppStorage("llm_model") private var model = ""
    @AppStorage("llm_base_url") private var baseURL = ""
    @AppStorage("terminal_theme") private var selectedThemeId = TerminalTheme.defaultTheme.id
    @State private var apiKey = ""
    @State private var showAPIKey = false
    @State private var saveMessage: String?
    var llmService: LLMService
    var themeManager: ThemeManager

    private var providerType: LLMProviderType {
        LLMProviderType(rawValue: providerTypeRaw) ?? .anthropic
    }

    var body: some View {
        Form {
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
        .frame(width: 450, height: 420)
        .onAppear {
            loadConfig()
        }
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
            try KeychainService.save(key: providerType.keychainKey, value: apiKey)

            // Register the provider with LLMService immediately
            let provider = llmService.createProvider(
                type: providerType,
                apiKey: apiKey,
                model: model,
                baseURL: baseURL
            )
            llmService.registerProvider(providerType, provider: provider)

            saveMessage = "配置已保存并生效"
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                saveMessage = nil
            }
        } catch {
            saveMessage = "保存失败: \(error.localizedDescription)"
        }
    }
}
