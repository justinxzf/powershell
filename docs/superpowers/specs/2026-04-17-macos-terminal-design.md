# PowerShell — macOS 智能终端设计文档

## Context

在 macOS 上缺少一个原生体验的、集成 AI 能力的终端应用。用户需要在多个终端会话之间快速切换，同时希望用自然语言代替复杂命令行操作。本项目旨在用 Swift + SwiftUI 构建一个 macOS 原生终端，核心特性：侧边栏多会话管理 + 自然语言转命令行。

## 技术栈

- **语言**: Swift
- **UI 框架**: SwiftUI (NavigationSplitView)
- **终端模拟**: SwiftTerm
- **NL 引擎**: 云端 LLM API（多 Provider 可配置）
- **密钥存储**: macOS Keychain
- **最低系统**: macOS 13.0 (Ventura)

## 架构: 单窗口 + 侧边栏

```
┌─────────────────────────────────────────────┐
│  App (WindowGroup)                          │
│  └─ NavigationSplitView                    │
│      ├─ SidebarView          │ TerminalView │
│      │  ├─ SessionListItem   │  ├─ SwiftTerm│
│      │  └─ AddSessionButton  │  ├─ NLInput  │
│      └─ Detail (terminal)    │  └─ Suggest  │
│                              │              │
└─────────────────────────────────────────────┘
```

## 核心模块

### 1. Views 层

- **SidebarView**: 会话列表，支持点击切换、+ 号新建、右键菜单（重命名/关闭）、活跃状态指示（绿色=活动/灰色=空闲）、可折叠为图标模式
- **TerminalView**: 主终端区域，嵌入 SwiftTerm 渲染引擎
- **NLInputBar**: NL 建议卡片，蓝色高亮显示建议命令，三个操作按钮：确认(Enter)/编辑/取消(Esc)
- **SettingsView**: LLM Provider 配置、API Key 设置、默认 Shell 选择

### 2. ViewModel 层

- **SessionManager**: 管理 Session CRUD、当前活跃会话切换、会话持久化
- **TerminalViewModel**: PTY 进程管理、输入输出流处理、命令历史
- **NLViewModel**: NL→命令转换调度、API 调用、确认/执行流程

### 3. Model 层

```swift
struct Session: Identifiable {
    let id: UUID
    var name: String
    var shellType: ShellType  // .bash, .zsh
    var isActive: Bool
}

struct TerminalState {
    var buffer: String
    var cursorPosition: Int
    var commandHistory: [String]
}

struct NLRequest {
    var input: String
    var suggestedCommand: String?
    var explanation: String?
    var isDangerous: Bool
    var status: NLStatus  // .detecting, .converting, .suggested, .confirmed, .cancelled
}

struct LLMConfig {
    var provider: LLMProvider  // .anthropic, .openAI
    var apiKey: String
    var model: String
}
```

### 4. Service 层

**PTYService**: fork/exec shell 进程，读写 PTY 文件描述符

**LLMService**: 多 Provider 抽象层
```swift
protocol LLMProvider {
    func convert(naturalLanguage: String, context: ShellContext) async throws -> CommandSuggestion
}

struct ShellContext {
    let cwd: String
    let shellType: ShellType
    let osInfo: String
    let recentHistory: [String]  // 最近5条命令
}

struct CommandSuggestion {
    let command: String
    let explanation: String?
    let isDangerous: Bool  // rm -rf, sudo, mkfs, dd 等
}
```

**NLDetector**: 纯本地检测，规则如下：
- 以已知命令开头 → 命令
- 包含 shell 语法字符（|, >, <, &&, ||, $, --, -, ./, ~/）→ 命令
- 包含中文字符 → NL
- 完整句式（"how to", "find all", "delete files"等）→ NL
- 默认 → 命令（宁可漏检不误判）

**KeychainService**: API Key 存储于 macOS Keychain

## 数据流

```
用户输入 → NLDetector
├─ 判定为命令 → PTYService 直接执行
└─ 判定为 NL → LLMService 转换 → CommandSuggestionView
    ├─ 确认(Enter) → PTYService 执行
    ├─ 编辑 → 建议命令填入输入框，用户修改后执行
    └─ 取消(Esc) → 清除建议
```

## 危险命令处理

LLM 返回 `isDangerous: true` 时，UI 显示红色警告标记，确认按钮需要二次确认。

## 依赖

- SwiftTerm: 终端模拟渲染（SPM 集成）
- 无其他第三方依赖

## 文件结构

```
PowerShell/
├── App/
│   └── PowerShellApp.swift
├── Views/
│   ├── SidebarView.swift
│   ├── TerminalView.swift
│   ├── NLInputBar.swift
│   ├── CommandSuggestionView.swift
│   └── SettingsView.swift
├── ViewModels/
│   ├── SessionManager.swift
│   ├── TerminalViewModel.swift
│   └── NLViewModel.swift
├── Models/
│   ├── Session.swift
│   ├── TerminalState.swift
│   ├── NLRequest.swift
│   └── LLMConfig.swift
├── Services/
│   ├── PTYService.swift
│   ├── LLMService.swift
│   ├── AnthropicProvider.swift
│   ├── OpenAIProvider.swift
│   ├── NLDetector.swift
│   └── KeychainService.swift
└── Utils/
    └── Constants.swift
```

## 验证方案

1. **侧边栏功能**: 创建3个会话，切换、重命名、关闭，验证 PTY 进程正确创建和销毁
2. **终端基础**: 在 SwiftTerm 中执行基本命令（ls, cd, git status），验证输入输出正常
3. **NL 检测**: 输入纯命令和纯自然语言，验证分类准确率
4. **NL 转换**: 输入自然语言，验证 LLM API 调用成功，建议命令合理
5. **确认流程**: 验证确认/编辑/取消三种操作行为正确
6. **危险命令**: 触发 isDangerous 标记，验证红色警告和二次确认
7. **Keychain**: 验证 API Key 存储和读取正常
