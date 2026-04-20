# Claude Code 终端通知方案

## 1. 功能点介绍

本方案为终端模拟器接入 Claude Code Hooks 事件，实现以下功能：

| 功能 | 说明 |
|------|------|
| **会话状态感知** | 自动检测 Claude Code 的启停，侧边栏显示紫色圆点指示器 |
| **NL 拦截旁路** | Claude Code 运行时自动关闭自然语言→命令转换拦截，避免误判 |
| **任务完成通知** | Claude Code 完成任务（Stop 事件）时弹出系统通知 |
| **权限请求通知** | Claude Code 请求权限批准时弹出通知，避免长时间无响应 |
| **空闲提示通知** | Claude Code 等待用户输入时弹出通知 |
| **通知点击跳转** | 点击通知自动切换到对应终端标签页并激活窗口 |
| **未读徽标** | 非当前标签页收到通知时，侧边栏显示红色未读计数 |
| **双通道通知** | App Bundle 模式使用原生 macOS 通知中心；Debug 模式使用浮窗横幅 |
| **端口自动发现** | 默认端口被占用时自动递增端口（9786~9796），Hook 脚本动态读取 |
| **调试日志** | 通知链路全量日志输出到 `~/.powershell/logs/debug.log`，支持日志轮转 |

### 支持的 Hook 事件

| 事件 | 触发时机 | 通知类型 |
|------|---------|---------|
| `SessionStart` | Claude Code 启动 | 侧边栏圆点变紫 + 跳过 NL 检测 |
| `SessionEnd` | Claude Code 退出 | 侧边栏圆点恢复 + 恢复 NL 检测 |
| `Notification` | 权限请求/空闲提示/授权成功/用户交互 | 弹出通知横幅 |
| `Stop` | Claude Code 完成任务 | 弹出"任务完成"通知 |

---

## 2. 使用步骤

### 前置条件

- macOS 14.0+
- Claude Code CLI 已安装并登录

### 自动配置（推荐）

PowerShell 启动时自动完成 Hook 配置，无需手动操作：

1. **Hook 脚本**：自动创建 `~/.powershell/hooks/powershell-hook.sh` 并赋予执行权限
2. **Claude Code Hooks**：自动在 `~/.claude/settings.json` 中合并 Hook 配置（保留已有配置）
3. **版本管理**：脚本内容变更时自动更新（通过版本文件 `~/.powershell/hooks/.script-version`）

可在 **设置 → Claude Code 集成** 中开关自动配置。关闭时自动清理所有 Hook 配置。

### 手动配置（可选）

如需手动配置，可按以下步骤操作：

**1. 创建 Hook 脚本**（`~/.powershell/hooks/powershell-hook.sh`）：

```bash
#!/bin/bash
# PowerShell notification hook
# Auto-managed by PowerShell app - do not edit manually
INPUT=$(cat)
PORT=$(cat ~/.powershell/hook-port 2>/dev/null || echo "9786")
curl -s -X POST "http://127.0.0.1:$PORT" \
  -H 'Content-Type: application/json' \
  -d "$INPUT" > /dev/null 2>&1
```

**2. 在 `~/.claude/settings.json` 中添加 `hooks` 配置**：

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "~/.powershell/hooks/powershell-hook.sh"
          }
        ]
      }
    ],
    "SessionEnd": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "~/.powershell/hooks/powershell-hook.sh"
          }
        ]
      }
    ],
    "Notification": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "~/.powershell/hooks/powershell-hook.sh"
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "~/.powershell/hooks/powershell-hook.sh"
          }
        ]
      }
    ]
  }
}
```

### 验证

1. 在 PowerShell 终端中运行 `claude`，观察侧边栏圆点是否变紫
2. Claude Code 执行完成后，观察是否弹出"任务完成"通知
3. 检查日志：`tail -f ~/.powershell/logs/debug.log`

---

## 3. 核心原理

### 整体架构

```
┌─────────────────────────────────────────────────────────────────┐
│  PowerShell 启动时：                                             │
│  HookConfigurator.configureIfNeeded()                           │
│  ├── 确保 ~/.powershell/hooks/powershell-hook.sh 存在且可执行   │
│  └── 合并 Hook 配置到 ~/.claude/settings.json                   │
│                                                                  │
│  Claude Code CLI                                                │
│  │ (Hook 事件触发)                                               │
│  ▼                                                              │
│  ~/.powershell/hooks/powershell-hook.sh                          │
│  │ 1. 从 stdin 读取 JSON                                        │
│  │ 2. 从 ~/.powershell/hook-port 读取端口                        │
│  │ 3. curl POST → 127.0.0.1:<port>                             │
│  ▼                                                              │
│  HookNotificationServer (NWListener, 本地 HTTP)                  │
│  │ 解析 HTTP body → HookEvent                                    │
│  ▼                                                              │
│  RootContentView (事件路由)                                      │
│  │                                                              │
│  ├── SessionStart → SessionManager.handleClaudeSessionStart()   │
│  │                    → session.claudeCodeActive = true          │
│  │                    → 侧边栏紫点 + skipNLDetection             │
│  │                                                              │
│  ├── SessionEnd → SessionManager.handleClaudeSessionEnd()       │
│  │                  → session.claudeCodeActive = false           │
│  │                                                              │
│  └── Notification / Stop → NotificationManager.send()           │
│                            → 原生通知 / 浮窗横幅                  │
│                            → 未读徽标                            │
└─────────────────────────────────────────────────────────────────┘
```

### 关键设计决策

**1. 统一使用 `command` 类型 Hook**

Claude Code 支持两种 Hook 类型：`http`（直接 POST）和 `command`（执行脚本）。本方案统一使用 `command` 类型，原因：

- `http` 类型的 URL 硬编码端口号，无法动态适配
- `command` 类型通过脚本中转，可以从 `~/.powershell/hook-port` 文件读取实际端口
- 端口自动发现后，Hook 脚本能正确路由到当前运行的 PowerShell 实例

**2. 端口自动发现**

默认监听 9786 端口，若被占用则依次尝试 9787~9796。绑定成功后将实际端口写入 `~/.powershell/hook-port`，Hook 脚本启动时读取该文件获取端口。这解决了多实例并行（如 Debug 模式与生产版同时运行）的端口冲突问题。

**3. 双通道通知降级**

```
App Bundle + 通知授权已授予 → UNUserNotificationCenter（原生 macOS 通知横幅）
App Bundle + 通知授权被拒绝 → FloatingNotificationBanner（右上角浮窗）
非 App Bundle（swift run）  → FloatingNotificationBanner（右上角浮窗）
```

`UNUserNotificationCenter` 在非 App Bundle 环境下调用会 crash（`bundleProxyForCurrentProcess is nil`），必须在调用前检查 bundle 类型。授权被拒绝时 `add()` 静默丢弃通知，因此需要缓存授权状态并在被拒时降级到浮窗。

---

## 4. 方案详情

### 4.0 HookConfigurator — Hook 自动配置

**文件**：`Sources/PowerShell/Services/HookConfigurator.swift`

应用启动时自动配置 Claude Code Hooks，用户无需手动操作：

- **脚本管理**：自动创建 `~/.powershell/hooks/powershell-hook.sh` 并赋予执行权限，版本变更时自动更新
- **配置合并**：安全合并 Hook 配置到 `~/.claude/settings.json`，保留用户已有配置和其他工具的 Hooks
- **幂等设计**：每次启动检查，仅在需要时写入（通过 `marker` 字符串 `"powershell-hook"` 检测已有配置）
- **迁移支持**：自动将旧路径 `~/.claude/hooks/powershell-hook.sh` 更新为新路径 `~/.powershell/hooks/powershell-hook.sh`
- **开关控制**：Settings UI 提供"Claude Code 集成"开关，关闭时自动清理所有 Hook 配置
- **版本管理**：通过 `~/.powershell/hooks/.script-version` 文件追踪脚本版本

```swift
HookConfigurator.shared.configureIfNeeded()  // 在 HookNotificationServer.start() 之前调用
```

### 4.1 HookNotificationServer — 本地 HTTP 服务

**文件**：`Sources/PowerShell/Services/HookNotificationServer.swift`

基于 Apple Network Framework 的 `NWListener` 实现 TCP HTTP 服务器：

- **端口发现**：启动时通过 `connect()` 系统调用检测端口是否可用，9786 被占用则递增尝试至 9796
- **端口文件**：绑定成功后将端口号写入 `~/.powershell/hook-port`，供 Hook 脚本读取
- **请求处理**：接收 HTTP POST 请求，提取 `\r\n\r\n` 之后的 body，解码为 `HookEvent`
- **容错**：JSON 解码失败时降级为纯文本 `notification` 事件；listener 失败时清理状态并删除端口文件
- **幂等启动**：重复调用 `start()` 不会重复绑定

```swift
struct HookEvent: Codable, Sendable {
    let hook_event_name: String      // "SessionStart" | "SessionEnd" | "Notification" | "Stop"
    let notification_type: String?   // "permission_prompt" | "idle_prompt" | "auth_success" | "elicitation_dialog"
    let message: String?
    let title: String?
    let session_id: String?          // Claude Code 的会话 ID
    let cwd: String?                 // 当前工作目录
    let last_assistant_message: String?
}
```

### 4.2 HookEvent 映射

`displayTitle` 和 `displayMessage` 将事件类型映射为中文展示文本：

| notification_type / hook_event_name | displayTitle | displayMessage |
|-------------------------------------|-------------|----------------|
| `permission_prompt` | 权限请求 | Claude 需要你的权限批准 |
| `idle_prompt` | 等待输入 | Claude 正在等待你的输入 |
| `auth_success` | 授权成功 | 授权已通过 |
| `elicitation_dialog` | 用户交互 | Claude 需要你的交互 |
| `Stop` / `stop` | 任务完成 | Claude Code 已完成任务 |
| 其他 | Claude Code | Claude Code 通知 |

`displayMessage` 优先级：`message` > `last_assistant_message`（截断 100 字符）> 默认文本。

### 4.3 NotificationManager — 双通道通知

**文件**：`Sources/PowerShell/Services/NotificationManager.swift`

#### 原生通知通道（UNUserNotificationCenter）

- 请求 `.alert` + `.sound` 授权
- 实现 `UNUserNotificationCenterDelegate`，前台通知展示为 `.banner, .sound`
- 通知 `userInfo` 携带 `sessionId`，点击时回调 `onNotificationClicked`
- 必须在 App Bundle 环境下使用，且授权已通过

#### 浮窗通知通道（FloatingNotificationBanner）

- `NSPanel` 子类，`level = .floating`，始终显示在最上层
- 右上角滑入动画（0.25s easeOut），关闭时向上滑出淡出（0.2s）
- 半透明深色背景（`white: 0.15, alpha: 0.92`），圆角 10pt
- 点击浮窗体跳转到对应终端标签页；点击 × 按钮关闭
- 最大宽度 320pt，body 最多 3 行

#### 授权状态缓存

```swift
private var authorizationGranted = false

private var canUseUNNotifications: Bool {
    isAppBundle && authorizationGranted
}
```

`requestAuthorization()` 在非 App Bundle 环境下直接跳过（避免 crash），授权结果缓存到 `authorizationGranted`，`send()` 据此选择通知通道。

### 4.4 SessionManager — 会话状态管理

**文件**：`Sources/PowerShell/ViewModels/SessionManager.swift`

核心数据结构：

```swift
private var claudeSessionMap: [String: UUID] = [:]  // Claude session_id → App Session UUID
```

| 方法 | 说明 |
|------|------|
| `handleClaudeSessionStart(claudeSessionId:)` | 将当前活跃终端与 Claude 会话关联，设置 `claudeCodeActive = true` |
| `handleClaudeSessionEnd(claudeSessionId:)` | 移除关联，设置 `claudeCodeActive = false` |
| `sessionForClaudeSession(_:)` | 通过 Claude session ID 反查 App session（用于通知定向） |

### 4.5 事件路由（RootContentView）

**文件**：`Sources/PowerShell/App/PowerShellApp.swift`

`.task` 修饰器中设置事件路由：

```swift
HookNotificationServer.shared.onHookNotification = { event in
    switch event.hook_event_name {
    case "SessionStart":
        sessionManager.handleClaudeSessionStart(claudeSessionId: claudeSessionId)
    case "SessionEnd":
        sessionManager.handleClaudeSessionEnd(claudeSessionId: claudeSessionId)
    default:
        // Notification / Stop 等事件
        let targetSessionId = sessionManager.sessionForClaudeSession(claudeSessionId)
            ?? sessionManager.activeSessionId
        NotificationManager.shared.send(title:body:sessionId:)
        sessionManager.incrementUnread(sessionId:)
    }
}
HookNotificationServer.shared.start()
```

通知目标定位策略：优先通过 `claudeSessionMap` 查找，找不到则使用当前活跃终端。

### 4.6 UI 响应

#### 侧边栏指示器（SidebarView）

```swift
Circle()
    .fill(session.claudeCodeActive ? Color.purple
         : (session.isActive ? Color.green : Color.gray.opacity(0.5)))
    .frame(width: 8, height: 8)
```

三态：**紫色** = Claude Code 运行中，**绿色** = Shell 活跃，**灰色** = 空闲。

#### NL 检测旁路（InterceptingTerminalView）

```swift
// TerminalDetailView.onChange
.onChange(of: session.claudeCodeActive) { _, active in
    terminalRef.terminalView?.skipNLDetection = active
}

// InterceptingTerminalView.send
if skipNLDetection {
    super.send(source: source, data: data)
    return  // 直接传递给 shell，跳过 NL 检测
}
```

### 4.7 OSC 9 辅助通道

**文件**：`Sources/PowerShell/Services/OutputMonitor.swift`

扫描终端输出字节流中的 OSC 9 转义序列（`\x1b]9;<msg>\x07`），作为通知的备用通道。当前 Hook 脚本未使用此机制，保留用于扩展。内置 2 秒冷却防止通知轰炸。

### 4.8 DebugLog — 调试日志

**文件**：`Sources/PowerShell/Services/DebugLog.swift`

- 日志同时输出到控制台（`print`）和文件（`~/.powershell/logs/debug.log`）
- 带毫秒级时间戳：`[2026-04-20 12:04:13.263]`
- 串行队列保证写入顺序，异步写入不阻塞主线程
- 超过 5MB 自动轮转（`debug.log` → `debug-prev.log`）

日志前缀约定：

| 前缀 | 来源 |
|------|------|
| `[HookServer]` | HookNotificationServer（连接、端口、解码） |
| `[HookRouter]` | RootContentView 中的事件路由逻辑 |
| `[NotificationManager]` | NotificationManager（授权、通道选择） |

---

## 5. 数据流详解

### Claude Code 启动

```
用户在终端输入 claude
  → Claude Code 启动，触发 SessionStart Hook
  → powershell-hook.sh 从 stdin 读取 JSON
  → 从 ~/.powershell/hook-port 读取端口（如 9786）
  → curl POST http://127.0.0.1:9786
  → HookNotificationServer 解码 HookEvent(hook_event_name: "SessionStart", session_id: "abc123")
  → SessionManager.handleClaudeSessionStart(claudeSessionId: "abc123")
      → claudeSessionMap["abc123"] = activeSessionId
      → session.claudeCodeActive = true
  → UI 响应：侧边栏圆点变紫 + skipNLDetection = true
```

### Claude Code 任务完成

```
Claude Code 执行完成，触发 Stop Hook
  → powershell-hook.sh POST JSON 到本地 HTTP 服务
  → HookNotificationServer 解码 HookEvent(hook_event_name: "Stop", last_assistant_message: "...")
  → RootContentView 路由到 default 分支
  → sessionForClaudeSession("abc123") 查找目标终端
  → NotificationManager.send(title: "PowerShell [终端 1]", body: "Claude Code 已完成任务")
  → 弹出通知横幅
  → incrementUnread(sessionId:) 更新未读徽标
```

### 通知点击跳转

```
用户点击通知横幅
  → UNUserNotificationCenterDelegate.didReceive / FloatingNotificationBanner.onClicked
  → NotificationManager.onNotificationClicked?(sessionId)
  → SessionManager.switchTo(sessionId:)
  → NSApp.activate(ignoringOtherApps: true)
  → 切换到对应终端标签页
```

---

## 6. 故障排查

| 现象 | 可能原因 | 排查方法 |
|------|---------|---------|
| 通知不弹出 | Hook 服务器未启动 | 检查日志中是否有 `[HookServer] listener ready` |
| 通知不弹出 | 端口冲突 | 检查 `lsof -i :9786`，查看 `~/.powershell/hook-port` 内容 |
| 通知不弹出 | 通知授权被拒且浮窗降级失败 | 检查日志中 `[NotificationManager]` 相关条目 |
| 侧边栏无紫点 | SessionStart 事件未触发 | 检查 `~/.claude/settings.json` 中 hooks 配置是否正确 |
| Hook 脚本不执行 | 脚本缺少执行权限 | `chmod +x ~/.claude/hooks/powershell-hook.sh` |
| Crash: bundleProxyForCurrentProcess is nil | 非 App Bundle 下调用了 UNUserNotificationCenter | 已修复：`requestAuthorization()` 会先检查 bundle 类型 |
| 多实例端口冲突 | 两个 PowerShell 实例同时运行 | 端口自动递增，Hook 脚本从端口文件读取 |

### 日志查看

```bash
# 实时查看
tail -f ~/.powershell/logs/debug.log

# 查看 Hook 服务器相关日志
grep "\[HookServer\]" ~/.powershell/logs/debug.log

# 查看通知相关日志
grep "\[NotificationManager\]\|\[HookRouter\]" ~/.powershell/logs/debug.log
```
