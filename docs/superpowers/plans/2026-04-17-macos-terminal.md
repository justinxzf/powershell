# PowerShell 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 构建一个 macOS 原生终端应用，支持侧边栏多会话管理和自然语言转命令行。

**Architecture:** SwiftUI NavigationSplitView 布局，左侧 SidebarView 管理会话列表，右侧 TerminalView 嵌入 SwiftTerm 渲染终端。NL 输入经本地 NLDetector 分类后，命令直接执行，自然语言经 LLM API 转换为命令建议，用户确认后执行。

**Tech Stack:** Swift, SwiftUI, SwiftTerm (SPM), macOS Keychain

---

## 文件结构

```
PowerShell/
├── PowerShell.xcodeproj
├── Package.swift
├── Sources/
│   └── PowerShell/
│       ├── App/
│       │   └── PowerShellApp.swift              — 应用入口, WindowGroup
│       ├── Views/
│       │   ├── SidebarView.swift                 — 侧边栏会话列表
│       │   ├── TerminalView.swift                 — SwiftTerm NSViewRepresentable 包装
│       │   ├── NLInputBar.swift                   — NL 建议卡片 UI
│       │   ├── CommandSuggestionView.swift         — 确认/编辑/取消操作栏
│       │   └── SettingsView.swift                 — LLM 配置页面
│       ├── ViewModels/
│       │   ├── SessionManager.swift               — 会话 CRUD, @Observable
│       │   ├── TerminalViewModel.swift             — PTY 生命周期, 输入输出
│       │   └── NLViewModel.swift                   — NL 检测 + LLM 调用 + 确认流程
│       ├── Models/
│       │   ├── Session.swift                       — Session, ShellType
│       │   ├── NLRequest.swift                     — NLRequest, NLStatus, CommandSuggestion, ShellContext
│       │   └── LLMConfig.swift                     — LLMConfig, LLMProvider enum
│       ├── Services/
│       │   ├── LLMService.swift                    — LLMProvider protocol + LLMService
│       │   ├── AnthropicProvider.swift              — Anthropic Claude API
│       │   ├── OpenAIProvider.swift                 — OpenAI GPT API
│       │   ├── NLDetector.swift                     — 本地 NL/命令检测
│       │   └── KeychainService.swift                — Keychain CRUD
│       └── Utils/
│           └── Constants.swift                      — 已知命令列表, 危险命令列表
└── Tests/
    └── PowerShellTests/
        ├── NLDetectorTests.swift
        └── KeychainServiceTests.swift
```

---

### Task 1: 项目脚手架 + SwiftTerm 集成

**Files:**
- Create: `Package.swift`
- Create: `Sources/PowerShell/App/PowerShellApp.swift`

- [ ] **Step 1: 初始化 Swift Package 项目**

```bash
cd /Users/bytedance/power_shell
mkdir -p Sources/PowerShell/App
```

- [ ] **Step 2: 创建 Package.swift**

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PowerShell",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "PowerShell", targets: ["PowerShell"])
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", from: "1.13.0")
    ],
    targets: [
        .executableTarget(
            name: "PowerShell",
            dependencies: ["SwiftTerm"],
            path: "Sources/PowerShell"
        ),
        .testTarget(
            name: "PowerShellTests",
            dependencies: ["PowerShell"],
            path: "Tests/PowerShellTests"
        )
    ]
)
```

- [ ] **Step 3: 创建应用入口**

```swift
// Sources/PowerShell/App/PowerShellApp.swift
import SwiftUI

@main
struct PowerShellApp: App {
    var body: some Scene {
        WindowGroup {
            Text("PowerShell - Hello")
                .frame(minWidth: 800, minHeight: 500)
        }
    }
}
```

- [ ] **Step 4: 解析依赖并构建**

```bash
swift package resolve
swift build
```

Expected: 编译成功，无错误

- [ ] **Step 5: 提交**

```bash
git init
echo ".build/" > .gitignore
echo ".superpowers/" >> .gitignore
git add -A
git commit -m "feat: initialize Swift Package project with SwiftTerm dependency"
```

---

### Task 2: Model 层 — Session, NLRequest, LLMConfig

**Files:**
- Create: `Sources/PowerShell/Models/Session.swift`
- Create: `Sources/PowerShell/Models/NLRequest.swift`
- Create: `Sources/PowerShell/Models/LLMConfig.swift`

- [ ] **Step 1: 创建 Session.swift**

```swift
// Sources/PowerShell/Models/Session.swift
import Foundation

enum ShellType: String, CaseIterable, Codable {
    case bash = "/bin/bash"
    case zsh = "/bin/zsh"

    var displayName: String {
        switch self {
        case .bash: return "bash"
        case .zsh: return "zsh"
        }
    }
}

struct Session: Identifiable, Codable {
    let id: UUID
    var name: String
    var shellType: ShellType
    var isActive: Bool

    init(id: UUID = UUID(), name: String, shellType: ShellType = .zsh, isActive: Bool = false) {
        self.id = id
        self.name = name
        self.shellType = shellType
        self.isActive = isActive
    }
}
```

- [ ] **Step 2: 创建 NLRequest.swift**

```swift
// Sources/PowerShell/Models/NLRequest.swift
import Foundation

enum NLStatus {
    case detecting
    case converting
    case suggested
    case confirmed
    case cancelled
    case error(String)
}

struct NLRequest {
    var input: String
    var suggestedCommand: String?
    var explanation: String?
    var isDangerous: Bool
    var status: NLStatus

    init(input: String) {
        self.input = input
        self.suggestedCommand = nil
        self.explanation = nil
        self.isDangerous = false
        self.status = .detecting
    }
}

struct ShellContext {
    let cwd: String
    let shellType: ShellType
    let osInfo: String
    let recentHistory: [String]

    static var current: ShellContext {
        ShellContext(
            cwd: FileManager.default.currentDirectoryPath,
            shellType: .zsh,
            osInfo: ProcessInfo.processInfo.operatingSystemVersionString,
            recentHistory: []
        )
    }
}

struct CommandSuggestion {
    let command: String
    let explanation: String?
    let isDangerous: Bool
}
```

- [ ] **Step 3: 创建 LLMConfig.swift**

```swift
// Sources/PowerShell/Models/LLMConfig.swift
import Foundation

enum LLMProviderType: String, CaseIterable, Codable {
    case anthropic
    case openAI

    var displayName: String {
        switch self {
        case .anthropic: return "Anthropic Claude"
        case .openAI: return "OpenAI GPT"
        }
    }

    var defaultModel: String {
        switch self {
        case .anthropic: return "claude-sonnet-4-6"
        case .openAI: return "gpt-4o"
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .anthropic: return "https://api.anthropic.com"
        case .openAI: return "https://api.openai.com"
        }
    }
}

struct LLMConfig: Codable {
    var providerType: LLMProviderType
    var apiKey: String
    var model: String
    var baseURL: String

    init(providerType: LLMProviderType = .anthropic, apiKey: String = "", model: String? = nil, baseURL: String? = nil) {
        self.providerType = providerType
        self.apiKey = apiKey
        self.model = model ?? providerType.defaultModel
        self.baseURL = baseURL ?? providerType.defaultBaseURL
    }
}
```

- [ ] **Step 4: 构建验证**

```bash
swift build
```

Expected: 编译成功

- [ ] **Step 5: 提交**

```bash
git add Sources/PowerShell/Models/
git commit -m "feat: add Session, NLRequest, LLMConfig models"
```

---

### Task 3: NLDetector — 自然语言检测引擎

**Files:**
- Create: `Sources/PowerShell/Utils/Constants.swift`
- Create: `Sources/PowerShell/Services/NLDetector.swift`
- Create: `Tests/PowerShellTests/NLDetectorTests.swift`

- [ ] **Step 1: 创建 Constants.swift**

```swift
// Sources/PowerShell/Utils/Constants.swift
import Foundation

enum Constants {
    static let knownCommands: Set<String> = [
        "ls", "cd", "pwd", "mkdir", "rm", "cp", "mv", "touch", "cat", "echo",
        "grep", "find", "sed", "awk", "sort", "uniq", "wc", "head", "tail",
        "chmod", "chown", "chgrp", "ln", "symlink", "tar", "gzip", "gunzip",
        "zip", "unzip", "curl", "wget", "ssh", "scp", "rsync", "ping",
        "ifconfig", "netstat", "lsof", "ps", "top", "kill", "killall",
        "df", "du", "free", "uptime", "whoami", "id", "su", "sudo",
        "apt", "brew", "npm", "yarn", "pnpm", "pip", "pip3", "conda",
        "gem", "cargo", "go", "rustc", "swift", "xcodebuild",
        "git", "docker", "kubectl", "helm", "terraform", "ansible",
        "make", "cmake", "gcc", "g++", "clang", "java", "javac",
        "python", "python3", "node", "ruby", "perl", "php",
        "vim", "nano", "less", "more", "man", "which", "whereis",
        "env", "export", "alias", "unalias", "source", "bash", "zsh",
        "sh", "fish", "open", "say", "defaults", "xattr", "launchctl",
        "tmux", "screen", "jq", "yq", "xargs", "tee", "diff", "patch",
        "base64", "md5", "shasum", "openssl", "ssh-keygen",
        "crontab", "at", "nohup", "disown", "trap", "wait",
        "test", "[", "[[", "true", "false", "return", "exit",
        "let", "expr", "bc", "date", "cal", "sleep", "time",
        "hexdump", "xxd", "strings", "file", "stat", "readlink",
        "dirname", "basename", "realpath", "mktemp", "install"
    ]

    static let dangerousPatterns: [String] = [
        "rm -rf /", "rm -rf /*", "rm -rf ~", "rm -rf ~/*",
        "mkfs", "dd if=", ":(){ :|:& };:",
        "> /dev/sda", "chmod -R 777 /",
        "wget.*| sh", "curl.*| sh"
    ]

    static let nlSentencePatterns: [String] = [
        "how to", "how do i", "how can i",
        "find all", "find every", "list all", "list every",
        "delete all", "delete every", "remove all", "remove every",
        "show me", "show all", "display all",
        "count all", "count the",
        "search for", "look for", "check if",
        "create a", "create an", "make a", "make an",
        "convert", "rename all",
        "what is", "what are", "which is",
        "where is", "where are",
        "sort by", "group by", "filter by"
    ]
}
```

- [ ] **Step 2: 创建 NLDetector.swift**

```swift
// Sources/PowerShell/Services/NLDetector.swift
import Foundation

enum InputType {
    case command
    case naturalLanguage
}

struct NLDetector {
    static func detect(_ input: String) -> InputType {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .command }

        // 包含中文字符 → NL
        if trimmed.contains(where: { $0.isChineseCharacter }) {
            return .naturalLanguage
        }

        // 以已知命令开头 → 命令
        let firstToken = trimmed.split(separator: " ", maxSplits: 1).first.map(String.init) ?? ""
        if Constants.knownCommands.contains(firstToken) {
            return .command
        }

        // 包含 shell 语法字符 → 命令
        let shellSyntaxPatterns: [Character] = ["|", ">", "<", "$", "~"]
        let shellSyntaxStrings = ["&&", "||", "--", "./"]
        if trimmed.contains(where: { shellSyntaxPatterns.contains($0) }) {
            return .command
        }
        if shellSyntaxStrings.contains(where: { trimmed.contains($0) }) {
            return .command
        }
        // 单独的 - 后跟字母 (如 -la, -v) → 命令
        if trimmed.hasPrefix("-") {
            return .command
        }

        // 匹配 NL 句式 → NL
        let lower = trimmed.lowercased()
        if Constants.nlSentencePatterns.contains(where: { lower.hasPrefix($0) }) {
            return .naturalLanguage
        }

        // 默认 → 命令
        return .command
    }
}

extension Character {
    var isChineseCharacter: Bool {
        guard let scalar = unicodeScalars.first else { return false }
        return (0x4E00...0x9FFF).contains(scalar.value) ||
               (0x3400...0x4DBF).contains(scalar.value) ||
               (0x3000...0x303F).contains(scalar.value) // 中文标点
    }
}
```

- [ ] **Step 3: 创建 NLDetectorTests.swift**

```swift
// Tests/PowerShellTests/NLDetectorTests.swift
import XCTest
@testable import PowerShell

final class NLDetectorTests: XCTestCase {
    // 命令检测
    func testKnownCommands() {
        XCTAssertEqual(NLDetector.detect("ls -la"), .command)
        XCTAssertEqual(NLDetector.detect("cd ~/Documents"), .command)
        XCTAssertEqual(NLDetector.detect("git status"), .command)
        XCTAssertEqual(NLDetector.detect("npm install"), .command)
        XCTAssertEqual(NLDetector.detect("make build"), .command)
        XCTAssertEqual(NLDetector.detect("docker ps"), .command)
    }

    // Shell 语法检测
    func testShellSyntax() {
        XCTAssertEqual(NLDetector.detect("ls | grep foo"), .command)
        XCTAssertEqual(NLDetector.detect("echo $HOME"), .command)
        XCTAssertEqual(NLDetector.detect("cat file > output"), .command)
        XCTAssertEqual(NLDetector.detect("make && make test"), .command)
        XCTAssertEqual(NLDetector.detect("./run.sh"), .command)
    }

    // 中文 NL 检测
    func testChineseInput() {
        XCTAssertEqual(NLDetector.detect("找出所有大于100MB的文件"), .naturalLanguage)
        XCTAssertEqual(NLDetector.detect("查看当前目录结构"), .naturalLanguage)
        XCTAssertEqual(NLDetector.detect("删除临时文件"), .naturalLanguage)
    }

    // 英文 NL 句式检测
    func testEnglishNL() {
        XCTAssertEqual(NLDetector.detect("how to find large files"), .naturalLanguage)
        XCTAssertEqual(NLDetector.detect("find all pdf files"), .naturalLanguage)
        XCTAssertEqual(NLDetector.detect("show me running processes"), .naturalLanguage)
    }

    // 默认为命令
    func testDefaultCommand() {
        XCTAssertEqual(NLDetector.detect("hello"), .command)
        XCTAssertEqual(NLDetector.detect(""), .command)
    }
}
```

- [ ] **Step 4: 运行测试**

```bash
swift test --filter NLDetectorTests
```

Expected: 所有测试通过

- [ ] **Step 5: 提交**

```bash
git add Sources/PowerShell/Utils/ Sources/PowerShell/Services/NLDetector.swift Tests/PowerShellTests/NLDetectorTests.swift
git commit -m "feat: add NLDetector with known commands, shell syntax, and NL pattern detection"
```

---

### Task 4: KeychainService — API Key 安全存储

**Files:**
- Create: `Sources/PowerShell/Services/KeychainService.swift`
- Create: `Tests/PowerShellTests/KeychainServiceTests.swift`

- [ ] **Step 1: 创建 KeychainService.swift**

```swift
// Sources/PowerShell/Services/KeychainService.swift
import Foundation
import Security

enum KeychainService {
    private static let serviceIdentifier = "com.powershell.app"

    static func save(key: String, value: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }

        // 先删除旧值
        delete(key: key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceIdentifier,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    static func load(key: String) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceIdentifier,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else {
            throw KeychainError.loadFailed(status)
        }
        guard let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
            throw KeychainError.decodingFailed
        }
        return value
    }

    static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceIdentifier,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }

    enum KeychainError: LocalizedError {
        case encodingFailed
        case saveFailed(OSStatus)
        case loadFailed(OSStatus)
        case decodingFailed

        var errorDescription: String? {
            switch self {
            case .encodingFailed: return "Failed to encode value to UTF-8"
            case .saveFailed(let status): return "Keychain save failed with status: \(status)"
            case .loadFailed(let status): return "Keychain load failed with status: \(status)"
            case .decodingFailed: return "Failed to decode value from UTF-8"
            }
        }
    }
}
```

- [ ] **Step 2: 创建 KeychainServiceTests.swift**

```swift
// Tests/PowerShellTests/KeychainServiceTests.swift
import XCTest
@testable import PowerShell

final class KeychainServiceTests: XCTestCase {
    private let testKey = "test-api-key-\(UUID().uuidString)"

    override func tearDown() {
        KeychainService.delete(key: testKey)
        super.tearDown()
    }

    func testSaveAndLoad() throws {
        let value = "sk-test-1234567890"
        try KeychainService.save(key: testKey, value: value)
        let loaded = try KeychainService.load(key: testKey)
        XCTAssertEqual(loaded, value)
    }

    func testLoadNonexistentKeyThrows() {
        XCTAssertThrowsError(try KeychainService.load(key: "nonexistent-key-\(UUID().uuidString)"))
    }

    func testDeleteRemovesKey() throws {
        try KeychainService.save(key: testKey, value: "temp")
        KeychainService.delete(key: testKey)
        XCTAssertThrowsError(try KeychainService.load(key: testKey))
    }

    func testSaveOverwrites() throws {
        try KeychainService.save(key: testKey, value: "old-value")
        try KeychainService.save(key: testKey, value: "new-value")
        let loaded = try KeychainService.load(key: testKey)
        XCTAssertEqual(loaded, "new-value")
    }
}
```

- [ ] **Step 3: 运行测试**

```bash
swift test --filter KeychainServiceTests
```

Expected: 所有测试通过

- [ ] **Step 4: 提交**

```bash
git add Sources/PowerShell/Services/KeychainService.swift Tests/PowerShellTests/KeychainServiceTests.swift
git commit -m "feat: add KeychainService for secure API key storage"
```

---

### Task 5: LLMService — 多 Provider 抽象层

**Files:**
- Create: `Sources/PowerShell/Services/LLMService.swift`
- Create: `Sources/PowerShell/Services/AnthropicProvider.swift`
- Create: `Sources/PowerShell/Services/OpenAIProvider.swift`

- [ ] **Step 1: 创建 LLMService.swift**

```swift
// Sources/PowerShell/Services/LLMService.swift
import Foundation

protocol LLMProviding {
    func convert(naturalLanguage: String, context: ShellContext) async throws -> CommandSuggestion
}

class LLMService: LLMProviding {
    private var providers: [LLMProviderType: LLMProviding] = [:]

    func registerProvider(_ type: LLMProviderType, provider: LLMProviding) {
        providers[type] = provider
    }

    func convert(naturalLanguage: String, context: ShellContext) async throws -> CommandSuggestion {
        // 使用第一个可用的 provider
        guard let provider = providers.values.first else {
            throw LLMError.noProviderConfigured
        }
        return try await provider.convert(naturalLanguage: naturalLanguage, context: context)
    }

    func convert(naturalLanguage: String, context: ShellContext, providerType: LLMProviderType) async throws -> CommandSuggestion {
        guard let provider = providers[providerType] else {
            throw LLMError.providerNotConfigured(providerType.rawValue)
        }
        return try await provider.convert(naturalLanguage: naturalLanguage, context: context)
    }

    enum LLMError: LocalizedError {
        case noProviderConfigured
        case providerNotConfigured(String)
        case invalidResponse
        case networkError(String)

        var errorDescription: String? {
            switch self {
            case .noProviderConfigured: return "No LLM provider configured"
            case .providerNotConfigured(let name): return "Provider '\(name)' not configured"
            case .invalidResponse: return "Invalid response from LLM API"
            case .networkError(let msg): return "Network error: \(msg)"
            }
        }
    }
}
```

- [ ] **Step 2: 创建 AnthropicProvider.swift**

```swift
// Sources/PowerShell/Services/AnthropicProvider.swift
import Foundation

class AnthropicProvider: LLMProviding {
    private let apiKey: String
    private let model: String
    private let baseURL: String

    init(apiKey: String, model: String = "claude-sonnet-4-6", baseURL: String = "https://api.anthropic.com") {
        self.apiKey = apiKey
        self.model = model
        self.baseURL = baseURL
    }

    func convert(naturalLanguage: String, context: ShellContext) async throws -> CommandSuggestion {
        let url = URL(string: "\(baseURL)/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let systemPrompt = """
        You are a command-line assistant. Convert the user's natural language request into a single shell command.
        Rules:
        - Output ONLY the command, nothing else. No explanation, no markdown, no backticks.
        - Target OS: macOS (\(context.osInfo))
        - Shell: \(context.shellType.displayName)
        - Current directory: \(context.cwd)
        - If the command is potentially dangerous (rm -rf, sudo, mkfs, dd, etc.), prefix your output with "DANGER:" followed by the command.
        - Prefer standard macOS/BSD commands over GNU/Linux-specific ones.
        """

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 256,
            "system": systemPrompt,
            "messages": [
                ["role": "user", "content": naturalLanguage]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw LLMService.LLMError.networkError("HTTP \(statusCode)")
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let content = json?["content"] as? [[String: Any]]
        let text = content?.first?["text"] as? String ?? ""

        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let isDangerous = trimmedText.hasPrefix("DANGER:")
        let command = isDangerous ? String(trimmedText.dropFirst(7)).trimmingCharacters(in: .whitespaces) : trimmedText

        guard !command.isEmpty else {
            throw LLMService.LLMError.invalidResponse
        }

        return CommandSuggestion(command: command, explanation: nil, isDangerous: isDangerous)
    }
}
```

- [ ] **Step 3: 创建 OpenAIProvider.swift**

```swift
// Sources/PowerShell/Services/OpenAIProvider.swift
import Foundation

class OpenAIProvider: LLMProviding {
    private let apiKey: String
    private let model: String
    private let baseURL: String

    init(apiKey: String, model: String = "gpt-4o", baseURL: String = "https://api.openai.com") {
        self.apiKey = apiKey
        self.model = model
        self.baseURL = baseURL
    }

    func convert(naturalLanguage: String, context: ShellContext) async throws -> CommandSuggestion {
        let url = URL(string: "\(baseURL)/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let systemPrompt = """
        You are a command-line assistant. Convert the user's natural language request into a single shell command.
        Rules:
        - Output ONLY the command, nothing else. No explanation, no markdown, no backticks.
        - Target OS: macOS (\(context.osInfo))
        - Shell: \(context.shellType.displayName)
        - Current directory: \(context.cwd)
        - If the command is potentially dangerous (rm -rf, sudo, mkfs, dd, etc.), prefix your output with "DANGER:" followed by the command.
        - Prefer standard macOS/BSD commands over GNU/Linux-specific ones.
        """

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 256,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": naturalLanguage]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw LLMService.LLMError.networkError("HTTP \(statusCode)")
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let choices = json?["choices"] as? [[String: Any]]
        let message = choices?.first?["message"] as? [String: Any]
        let text = message?["content"] as? String ?? ""

        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let isDangerous = trimmedText.hasPrefix("DANGER:")
        let command = isDangerous ? String(trimmedText.dropFirst(7)).trimmingCharacters(in: .whitespaces) : trimmedText

        guard !command.isEmpty else {
            throw LLMService.LLMError.invalidResponse
        }

        return CommandSuggestion(command: command, explanation: nil, isDangerous: isDangerous)
    }
}
```

- [ ] **Step 4: 构建验证**

```bash
swift build
```

Expected: 编译成功

- [ ] **Step 5: 提交**

```bash
git add Sources/PowerShell/Services/LLMService.swift Sources/PowerShell/Services/AnthropicProvider.swift Sources/PowerShell/Services/OpenAIProvider.swift
git commit -m "feat: add LLMService with Anthropic and OpenAI providers"
```

---

### Task 6: TerminalView — SwiftTerm SwiftUI 包装

**Files:**
- Create: `Sources/PowerShell/Views/TerminalView.swift`

- [ ] **Step 1: 创建 TerminalView.swift**

```swift
// Sources/PowerShell/Views/TerminalView.swift
import SwiftUI
import SwiftTerm

struct TerminalPaneView: NSViewRepresentable {
    let shellType: ShellType
    let onTitleChanged: ((String) -> Void)?
    let onDirectoryChanged: ((String?) -> Void)?
    let onProcessTerminated: ((Int32?) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let terminal = LocalProcessTerminalView(frame: .zero)
        terminal.processDelegate = context.coordinator
        terminal.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        terminal.nativeBackgroundColor = NSColor(red: 0.12, green: 0.12, blue: 0.12, alpha: 1)
        terminal.nativeForegroundColor = NSColor(red: 0.8, green: 0.8, blue: 0.8, alpha: 1)
        terminal.startProcess(executable: shellType.rawValue)
        return terminal
    }

    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {}

    class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
        let parent: TerminalPaneView

        init(parent: TerminalPaneView) {
            self.parent = parent
        }

        func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

        func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
            parent.onTitleChanged?(title)
        }

        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
            parent.onDirectoryChanged?(directory)
        }

        func processTerminated(source: TerminalView, exitCode: Int32?) {
            parent.onProcessTerminated?(exitCode)
        }
    }
}
```

- [ ] **Step 2: 构建验证**

```bash
swift build
```

Expected: 编译成功

- [ ] **Step 3: 提交**

```bash
git add Sources/PowerShell/Views/TerminalView.swift
git commit -m "feat: add TerminalPaneView wrapping SwiftTerm for SwiftUI"
```

---

### Task 7: SessionManager — 会话管理 ViewModel

**Files:**
- Create: `Sources/PowerShell/ViewModels/SessionManager.swift`

- [ ] **Step 1: 创建 SessionManager.swift**

```swift
// Sources/PowerShell/ViewModels/SessionManager.swift
import Foundation
import Observation

@Observable
class SessionManager {
    var sessions: [Session] = []
    var activeSessionId: UUID?

    var activeSession: Session? {
        sessions.first { $0.id == activeSessionId }
    }

    func createSession(name: String? = nil, shellType: ShellType = .zsh) -> Session {
        let sessionName = name ?? "终端 \(sessions.count + 1)"
        let session = Session(name: sessionName, shellType: shellType)
        sessions.append(session)
        if activeSessionId == nil {
            activeSessionId = session.id
        }
        return session
    }

    func switchTo(sessionId: UUID) {
        guard sessions.contains(where: { $0.id == sessionId }) else { return }
        activeSessionId = sessionId
    }

    func rename(sessionId: UUID, newName: String) {
        if let index = sessions.firstIndex(where: { $0.id == sessionId }) {
            sessions[index].name = newName
        }
    }

    func delete(sessionId: UUID) {
        sessions.removeAll { $0.id == sessionId }
        if activeSessionId == sessionId {
            activeSessionId = sessions.first?.id
        }
    }

    func setActiveActivity(sessionId: UUID, isActive: Bool) {
        if let index = sessions.firstIndex(where: { $0.id == sessionId }) {
            sessions[index].isActive = isActive
        }
    }
}
```

- [ ] **Step 2: 构建验证**

```bash
swift build
```

Expected: 编译成功

- [ ] **Step 3: 提交**

```bash
git add Sources/PowerShell/ViewModels/SessionManager.swift
git commit -m "feat: add SessionManager for session CRUD and switching"
```

---

### Task 8: NLViewModel — NL 检测 + LLM 调用 + 确认流程

**Files:**
- Create: `Sources/PowerShell/ViewModels/NLViewModel.swift`

- [ ] **Step 1: 创建 NLViewModel.swift**

```swift
// Sources/PowerShell/ViewModels/NLViewModel.swift
import Foundation
import Observation

@Observable
class NLViewModel {
    var currentRequest: NLRequest?
    var isConverting = false

    private let llmService: LLMService
    private let nlDetector = NLDetector.self

    init(llmService: LLMService) {
        self.llmService = llmService
    }

    func processInput(_ input: String, context: ShellContext) async -> InputType {
        let inputType = nlDetector.detect(input)

        if inputType == .naturalLanguage {
            currentRequest = NLRequest(input: input)
            await convertToCommand(context: context)
        }

        return inputType
    }

    func confirmSuggestion() -> String? {
        guard let request = currentRequest, let command = request.suggestedCommand else { return nil }
        currentRequest = nil
        return command
    }

    func editSuggestion() -> String? {
        guard let request = currentRequest else { return nil }
        let command = request.suggestedCommand ?? request.input
        currentRequest = nil
        return command
    }

    func cancelSuggestion() {
        currentRequest = nil
    }

    private func convertToCommand(context: ShellContext) async {
        guard let request = currentRequest else { return }
        currentRequest?.status = .converting
        isConverting = true

        do {
            let suggestion = try await llmService.convert(
                naturalLanguage: request.input,
                context: context
            )
            currentRequest?.suggestedCommand = suggestion.command
            currentRequest?.explanation = suggestion.explanation
            currentRequest?.isDangerous = suggestion.isDangerous
            currentRequest?.status = .suggested
        } catch {
            currentRequest?.status = .error(error.localizedDescription)
        }

        isConverting = false
    }
}
```

- [ ] **Step 2: 构建验证**

```bash
swift build
```

Expected: 编译成功

- [ ] **Step 3: 提交**

```bash
git add Sources/PowerShell/ViewModels/NLViewModel.swift
git commit -m "feat: add NLViewModel for NL detection, LLM conversion, and confirmation flow"
```

---

### Task 9: SidebarView — 侧边栏 UI

**Files:**
- Create: `Sources/PowerShell/Views/SidebarView.swift`

- [ ] **Step 1: 创建 SidebarView.swift**

```swift
// Sources/PowerShell/Views/SidebarView.swift
import SwiftUI

struct SidebarView: View {
    @Bindable var sessionManager: SessionManager
    @State private var isNewSessionPopoverVisible = false

    var body: some View {
        List(selection: $sessionManager.activeSessionId) {
            ForEach(sessionManager.sessions) { session in
                SidebarItemRow(session: session, isSelected: session.id == sessionManager.activeSessionId)
                    .tag(session.id)
                    .contextMenu {
                        Button("重命名") {
                            // TODO: inline rename
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

                Button {
                    // Open settings
                } label: {
                    Image(systemName: "gearshape")
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }
            .padding(8)
            .background(.bar)
        }
    }
}

struct SidebarItemRow: View {
    let session: Session
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(session.isActive ? Color.green : Color.gray.opacity(0.5))
                .frame(width: 8, height: 8)
            Text(session.name)
                .lineLimit(1)
            Spacer()
            Text(session.shellType.displayName)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
```

- [ ] **Step 2: 构建验证**

```bash
swift build
```

Expected: 编译成功

- [ ] **Step 3: 提交**

```bash
git add Sources/PowerShell/Views/SidebarView.swift
git commit -m "feat: add SidebarView with session list, add button, and context menu"
```

---

### Task 10: NLInputBar + CommandSuggestionView — NL 交互 UI

**Files:**
- Create: `Sources/PowerShell/Views/NLInputBar.swift`
- Create: `Sources/PowerShell/Views/CommandSuggestionView.swift`

- [ ] **Step 1: 创建 CommandSuggestionView.swift**

```swift
// Sources/PowerShell/Views/CommandSuggestionView.swift
import SwiftUI

struct CommandSuggestionView: View {
    let request: NLRequest
    let onConfirm: () -> Void
    let onEdit: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundStyle(.blue)
                Text("检测到自然语言")
                    .font(.caption)
                    .foregroundStyle(.blue)
                Spacer()
                if request.isDangerous {
                    Label("危险命令", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Text(request.input)
                .font(.callout)
                .foregroundStyle(.secondary)

            if let command = request.suggestedCommand {
                Text(command)
                    .font(.system(.body, design: .monospaced))
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .textBackgroundColor))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(request.isDangerous ? Color.red : Color.blue.opacity(0.3), lineWidth: 1)
                    )
            }

            HStack(spacing: 8) {
                Button("确认执行 (↵)") { onConfirm() }
                    .buttonStyle(.borderedProminent)
                    .tint(request.isDangerous ? .red : .blue)

                Button("编辑命令") { onEdit() }
                    .buttonStyle(.bordered)

                Button("取消 (Esc)") { onCancel() }
                    .buttonStyle(.bordered)

                Spacer()
            }
        }
        .padding(12)
        .background(Color.blue.opacity(0.05))
        .cornerRadius(8)
    }
}
```

- [ ] **Step 2: 创建 NLInputBar.swift**

```swift
// Sources/PowerShell/Views/NLInputBar.swift
import SwiftUI

struct NLInputBar: View {
    @Binding var inputText: String
    let nlRequest: NLRequest?
    let isConverting: Bool
    let onSubmit: (String) -> Void
    let onConfirmSuggestion: () -> Void
    let onEditSuggestion: () -> Void
    let onCancelSuggestion: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // NL 建议卡片
            if let request = nlRequest {
                switch request.status {
                case .converting:
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                        Text("正在转换...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.blue.opacity(0.05))

                case .suggested:
                    CommandSuggestionView(
                        request: request,
                        onConfirm: onConfirmSuggestion,
                        onEdit: onEditSuggestion,
                        onCancel: onCancelSuggestion
                    )

                case .error(let message):
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.red)
                        Spacer()
                        Button("取消") { onCancelSuggestion() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                    .padding(12)

                default:
                    EmptyView()
                }
            }

            Divider()

            // 输入栏
            HStack(spacing: 8) {
                TextField("输入命令或自然语言...", text: $inputText)
                    .textFieldStyle(.plain)
                    .font(.system(.body, design: .monospaced))
                    .onSubmit {
                        let text = inputText.trimmingCharacters(in: .whitespaces)
                        guard !text.isEmpty else { return }
                        onSubmit(text)
                        inputText = ""
                    }

                Button {
                    let text = inputText.trimmingCharacters(in: .whitespaces)
                    guard !text.isEmpty else { return }
                    onSubmit(text)
                    inputText = ""
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(.bar)
    }
}
```

- [ ] **Step 3: 构建验证**

```bash
swift build
```

Expected: 编译成功

- [ ] **Step 4: 提交**

```bash
git add Sources/PowerShell/Views/NLInputBar.swift Sources/PowerShell/Views/CommandSuggestionView.swift
git commit -m "feat: add NLInputBar and CommandSuggestionView for NL interaction UI"
```

---

### Task 11: SettingsView — LLM 配置页面

**Files:**
- Create: `Sources/PowerShell/Views/SettingsView.swift`

- [ ] **Step 1: 创建 SettingsView.swift**

```swift
// Sources/PowerShell/Views/SettingsView.swift
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
        model = providerType.defaultModel
        baseURL = providerType.defaultBaseURL
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
```

- [ ] **Step 2: 构建验证**

```bash
swift build
```

Expected: 编译成功

- [ ] **Step 3: 提交**

```bash
git add Sources/PowerShell/Views/SettingsView.swift
git commit -m "feat: add SettingsView for LLM provider and API key configuration"
```

---

### Task 12: 组装 — PowerShellApp 主入口

**Files:**
- Modify: `Sources/PowerShell/App/PowerShellApp.swift`

- [ ] **Step 1: 重写 PowerShellApp.swift**

```swift
// Sources/PowerShell/App/PowerShellApp.swift
import SwiftUI

@main
struct PowerShellApp: App {
    @State private var sessionManager = SessionManager()
    @State private var nlViewModel: NLViewModel
    @State private var inputText = ""

    init() {
        let llmService = LLMService()
        _nlViewModel = State(wrappedValue: NLViewModel(llmService: llmService))
    }

    var body: some Scene {
        WindowGroup {
            NavigationSplitView {
                SidebarView(sessionManager: sessionManager)
            } detail: {
                if let activeSession = sessionManager.activeSession {
                    TerminalDetailView(
                        session: activeSession,
                        nlViewModel: nlViewModel,
                        inputText: $inputText
                    )
                } else {
                    ContentUnavailableView(
                        "没有活跃终端",
                        systemImage: "terminal",
                        description: Text("点击侧边栏 + 按钮创建新终端")
                    )
                }
            }
            .frame(minWidth: 800, minHeight: 500)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("新建终端") {
                    _ = sessionManager.createSession()
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }

        Settings {
            SettingsView()
        }
    }
}

struct TerminalDetailView: View {
    let session: Session
    @Bindable var nlViewModel: NLViewModel
    @Binding var inputText: String

    var body: some View {
        VStack(spacing: 0) {
            // 终端标题栏
            HStack {
                Circle().fill(session.isActive ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)
                Text(session.name)
                    .font(.headline)
                Spacer()
                Text(session.shellType.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.bar)

            // 终端区域
            TerminalPaneView(
                shellType: session.shellType,
                onTitleChanged: { _ in },
                onDirectoryChanged: { _ in },
                onProcessTerminated: { _ in }
            )

            // NL 输入栏
            NLInputBar(
                inputText: $inputText,
                nlRequest: nlViewModel.currentRequest,
                isConverting: nlViewModel.isConverting,
                onSubmit: { text in
                    handleSubmit(text)
                },
                onConfirmSuggestion: {
                    if let command = nlViewModel.confirmSuggestion() {
                        sendToTerminal(command)
                    }
                },
                onEditSuggestion: {
                    if let command = nlViewModel.editSuggestion() {
                        inputText = command
                    }
                },
                onCancelSuggestion: {
                    nlViewModel.cancelSuggestion()
                }
            )
        }
    }

    private func handleSubmit(_ text: String) {
        Task {
            let context = ShellContext(
                cwd: FileManager.default.currentDirectoryPath,
                shellType: session.shellType,
                osInfo: ProcessInfo.processInfo.operatingSystemVersionString,
                recentHistory: []
            )
            let inputType = await nlViewModel.processInput(text, context: context)
            if inputType == .command {
                sendToTerminal(text)
            }
        }
    }

    private func sendToTerminal(_ command: String) {
        // SwiftTerm send will be wired through TerminalViewModel in future iteration
        // For now, the input goes through the NLInputBar flow
    }
}
```

- [ ] **Step 2: 构建验证**

```bash
swift build
```

Expected: 编译成功

- [ ] **Step 3: 提交**

```bash
git add Sources/PowerShell/App/PowerShellApp.swift
git commit -m "feat: assemble PowerShellApp with NavigationSplitView, sidebar, and terminal detail"
```

---

### Task 13: 端到端集成测试

**Files:**
- Modify: 无新文件

- [ ] **Step 1: 构建并运行应用**

```bash
swift build
.build/debug/PowerShell
```

验证：
1. 应用窗口打开，显示侧边栏 + 主区域
2. 点击 + 按钮可创建新终端会话
3. 侧边栏显示会话列表，点击可切换
4. 终端区域显示 shell 提示符，可输入基本命令（ls, pwd）
5. 右键侧边栏项目显示重命名/关闭菜单
6. 关闭会话后切换到其他会话

- [ ] **Step 2: 测试 NL 检测**

在输入栏输入：
- `ls -la` → 应直接执行（命令）
- `找出所有大于100MB的文件` → 应显示 NL 建议卡片（需配置 API Key）

- [ ] **Step 3: 测试 Settings**

打开设置页面，配置 API Key，保存后验证 Keychain 存储。

- [ ] **Step 4: 提交**

```bash
git add -A
git commit -m "feat: complete PowerShell v1.0 — macOS terminal with sidebar and NL input"
```
