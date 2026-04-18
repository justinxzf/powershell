# Claude Code 会话检测技术方案

## 背景

PowerShell 是一个 macOS 终端模拟器，内置自然语言→Shell 命令转换功能。当用户在终端中运行 Claude Code CLI 时，自然语言拦截器会误判 Claude Code 的交互内容，导致体验冲突。需要一种机制让 App 感知 Claude Code 的启停，并做出响应。

## 核心问题

1. **NL 拦截冲突**：Claude Code 会话中，用户输入和 Claude 输出都是自然语言，NL 拦截器会错误触发
2. **状态不可见**：用户无法直观知道哪个终端标签页正在运行 Claude Code
3. **通知缺失**：Claude Code 的权限请求、空闲提示等事件无法以原生通知形式触达用户

## 技术方案

### 架构总览

```
Claude Code CLI
    │ (Hook 事件触发)
    ▼
Shell Script / HTTP Hook
    │ POST JSON → 127.0.0.1:9786
    ▼
HookNotificationServer (NWListener)
    │ 解析为 HookEvent
    ▼
PowerShellApp (事件分发)
    │
    ├── SessionStart → SessionManager.handleClaudeSessionStart()
    ├── SessionEnd   → SessionManager.handleClaudeSessionEnd()
    └── Notification/Stop → NotificationManager.send() + unread 徽标
    ▼
Session.claudeCodeActive (Observable)
    │
    ├── SidebarView: 紫色圆点指示器
    └── InterceptingTerminalView.skipNLDetection: 跳过 NL 检测
```

### 1. Hook 配置

Claude Code 支持四种 Hook 事件，配置在 `~/.claude/settings.json`：

| 事件 | Hook 类型 | 说明 |
|------|----------|------|
| SessionStart | `command` | 执行 shell 脚本，脚本内 curl 到本地 HTTP 服务 |
| SessionEnd | `http` | 直接 POST 到本地 HTTP 服务 |
| Notification | `http` | 直接 POST，含权限请求、空闲提示等 |
| Stop | `http` | 直接 POST，任务完成时触发 |

**SessionStart 使用 `command` 类型而非 `http`**：Claude Code 的 SessionStart 事件仅支持 `command` 类型，HTTP 类型会被静默忽略。因此通过 shell 脚本中转。

Shell 脚本 (`~/.claude/hooks/session-start.sh`) 内容：

```bash
#!/bin/bash
INPUT=$(cat)
curl -s -X POST http://127.0.0.1:9786 \
  -H 'Content-Type: application/json' \
  -d "$INPUT" > /dev/null 2>&1
```

### 2. HookNotificationServer — 本地 HTTP 服务

**文件**：`Services/HookNotificationServer.swift`

- 基于 `NWListener` (Network framework) 监听 TCP 9786 端口
- 单例模式，`@MainActor` 标注
- 接收 POST 请求，提取 HTTP body 解码为 `HookEvent`
- JSON 解码失败时降级为 `notification` 类型事件（容错）
- 通过 `onHookNotification` 回调分发事件

```swift
struct HookEvent: Codable, Sendable {
    let hook_event_name: String      // "SessionStart" | "SessionEnd" | "Notification" | "Stop"
    let notification_type: String?   // "permission_prompt" | "idle_prompt" 等
    let message: String?
    let title: String?
    let session_id: String?          // Claude Code 的会话 ID
    let cwd: String?                 // 当前工作目录
    let last_assistant_message: String?
}
```

`displayTitle` 和 `displayMessage` 将 `notification_type` 映射为中文字符串（如 `"permission_prompt"` → "权限请求"）。

### 3. SessionManager — 会话状态管理

**文件**：`ViewModels/SessionManager.swift`

核心数据结构：

```swift
private var claudeSessionMap: [String: UUID] = [:]  // Claude session_id → App Session UUID
```

关键方法：

- **`handleClaudeSessionStart(claudeSessionId:)`**：将当前活跃终端与 Claude 会话关联，设置 `session.claudeCodeActive = true`
- **`handleClaudeSessionEnd(claudeSessionId:)`**：移除关联，设置 `session.claudeCodeActive = false`
- **`sessionForClaudeSession(_:)`**：通过 Claude session ID 反查 App session（用于 Notification 事件定向）
- **`sessionForCwd(_:)`**：通过工作目录匹配的兜底方案

### 4. Session 模型

**文件**：`Models/Session.swift`

```swift
var claudeCodeActive: Bool = false
```

单一布尔值，通过 `@Observable` 驱动所有下游 UI 更新。

### 5. UI 层响应

#### 侧边栏指示器 (`SidebarView.swift`)

```swift
Circle()
    .fill(session.claudeCodeActive ? Color.purple
         : (session.isActive ? Color.green : Color.gray.opacity(0.5)))
    .frame(width: 8, height: 8)
```

三态指示：**紫色** = Claude Code 运行中，**绿色** = Shell 活跃，**灰色** = 空闲。

#### NL 检测跳过 (`TerminalView.swift`)

`InterceptingTerminalView` 的 `skipNLDetection` 标志控制 NL 拦截：

```swift
if skipNLDetection {
    super.send(source: source, data: data)
    return  // 直接传递给 shell，跳过 NL 检测
}
```

通过 `TerminalDetailView` 的 `.onChange` 桥接：

```swift
.onChange(of: session.claudeCodeActive) { _, active in
    terminalRef.terminalView?.skipNLDetection = active
}
```

### 6. 通知推送

**文件**：`Services/NotificationManager.swift`

双通道通知：

- **App Bundle 模式**：`UNUserNotificationCenter` 原生 macOS 通知横幅，支持点击跳转到对应终端标签
- **Debug 模式**（`swift run`）：`FloatingNotificationBanner`（`NSPanel`，右上角滑入的半透明浮窗）

### 7. OSC 9 辅助通道

**文件**：`Services/OutputMonitor.swift`

扫描终端输出字节流中的 OSC 9 转义序列（`\x1b]9;<msg>\x07`），作为通知的备用通道。当前 Hook 脚本未使用此机制，保留用于扩展。

## 数据流详解

### Claude Code 启动

```
用户输入 claude → Claude Code 启动
    → SessionStart Hook 触发
    → session-start.sh 从 stdin 读取 JSON，POST 到 127.0.0.1:9786
    → HookNotificationServer 解析 HookEvent
    → SessionManager.handleClaudeSessionStart()
        → claudeSessionMap[session_id] = activeSessionId
        → session.claudeCodeActive = true
    → UI 响应：
        侧边栏圆点变紫色
        skipNLDetection = true（NL 拦截关闭）
```

### Claude Code 退出

```
用户输入 /exit → Claude Code 退出
    → SessionEnd Hook 触发（HTTP 直连）
    → HookNotificationServer 解析 HookEvent
    → SessionManager.handleClaudeSessionEnd()
        → claudeSessionMap 移除对应条目
        → session.claudeCodeActive = false
    → UI 响应：
        侧边栏圆点恢复绿色/灰色
        skipNLDetection = false（NL 拦截恢复）
```

### 通知事件

```
Claude Code 触发权限请求/空闲提示/任务完成
    → Notification/Stop Hook 触发（HTTP 直连）
    → HookNotificationServer 解析 HookEvent
    → 查找目标 session（sessionForClaudeSession 或 activeSessionId）
    → NotificationManager.send(title, body, sessionId)
        → 原生通知 / 浮窗
    → sessionManager.incrementUnread(sessionId)
        → 侧边栏红色未读徽标
```

## 设计考量

1. **Hook 类型不对称**：SessionStart 仅支持 `command` 类型，其余三个支持 `http`。Shell 脚本本质是 HTTP 代理，确保统一入口。

2. **会话关联策略**：以 `activeSessionId` 为主关联 Claude 会话，`sessionForCwd` 作为工作目录匹配的兜底。存在极小概率的时间窗口问题（Hook 触发时用户已切换标签）。

3. **NL 拦截旁路层级**：`skipNLDetection` 在终端视图层实现，`NLViewModel` 不感知 Claude Code 状态。关注点分离清晰——拦截点即控制点。

4. **容错**：HookNotificationServer 对 JSON 解码失败有降级处理；NotificationManager 对非 Bundle 运行有浮窗兜底。

5. **端口选择**：9786 为固定端口，全局单例。如果端口被占用，App 内终端仍正常工作，仅 Hook 功能不可用。
