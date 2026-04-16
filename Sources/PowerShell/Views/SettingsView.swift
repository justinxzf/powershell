import SwiftUI

struct SettingsView: View {
    @AppStorage("llm_provider_type") private var providerTypeRaw = LLMProviderType.anthropic.rawValue
    @AppStorage("llm_model") private var model = ""
    @AppStorage("llm_base_url") private var baseURL = ""
    @State private var apiKey = ""
    @State private var showAPIKey = false
    @State private var saveMessage: String?

    private var providerType: LLMProviderType {
        LLMProviderType(rawValue: providerTypeRaw) ?? .anthropic
    }

    private var defaultModel: String {
        switch providerType {
        case .anthropic: return "claude-sonnet-4-20250514"
        case .openAI: return "gpt-4o"
        }
    }

    private var defaultBaseURL: String {
        switch providerType {
        case .anthropic: return "https://api.anthropic.com"
        case .openAI: return "https://api.openai.com"
        }
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
                    model = defaultModel
                    baseURL = defaultBaseURL
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

            Section {
                Button("保存配置") {
                    saveConfig()
                }
                .buttonStyle(.borderedProminent)

                if let message = saveMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 450, height: 350)
        .onAppear {
            loadConfig()
        }
    }

    private func loadConfig() {
        if model.isEmpty {
            model = defaultModel
        }
        if baseURL.isEmpty {
            baseURL = defaultBaseURL
        }
        apiKey = (try? KeychainService.load(key: "llm_api_key_\(providerTypeRaw)")) ?? ""
    }

    private func saveConfig() {
        do {
            try KeychainService.save(key: "llm_api_key_\(providerTypeRaw)", value: apiKey)
            saveMessage = "配置已保存"
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                saveMessage = nil
            }
        } catch {
            saveMessage = "保存失败: \(error.localizedDescription)"
        }
    }
}
