---
name: notification-debug
description: 排查 PowerShell 通知栏不展示问题。当用户反馈 Claude Code 通知弹窗不显示时调用此 Skill，通过分析日志文件定位问题并给出修复方案。
---

# PowerShell 通知栏不展示问题排查

## 适用场景

当用户报告以下问题时调用此 Skill：
- PowerShell 中运行 Claude Code，但通知弹窗不显示
- 通知偶尔显示偶尔不显示
- 某些 tab 的通知不显示，其他 tab 正常
- 升级后通知完全不工作

## 前置要求：获取日志

首先使用 AskUserQuestion 让用户选择日志来源：

**问题**：「请选择通知排查的日志来源」
- **选项 1**：`读取默认日志` — 读取 `~/.powershell/logs/debug.log`（推荐）
- **选项 2**：`手动输入路径` — 用户自定义日志文件路径

根据用户选择，使用 Read 工具读取对应的日志文件。如果日志文件不存在或为空，直接跳到「无日志排查」部分。

## 排查流程

### 第 1 步：确认 Hook 服务器是否启动

在日志中搜索 `[HookServer]`：

```
[HookServer] started on port 9786
```

**正常**：有 `started on port` 日志，记录了端口号。

**异常 A**：无任何 `[HookServer]` 日志 → Hook 服务器未启动，检查：
- `HookNotificationServer.shared.start()` 是否被调用（在 `PowerShellApp.swift` 的 `.task` 中）
- 是否所有端口 9786-9796 都被占用（日志会有 `all ports ... are in use`）

**异常 B**：有 `bind error` → 端口绑定失败，可能是权限问题或端口冲突。

**修复**：
- 端口占用：`lsof -i :9786` 查看占用进程，kill 或等待释放
- 权限问题：检查 macOS 防火墙设置

---

### 第 2 步：确认 Hook 脚本是否配置

在日志中搜索 `[HookConfigurator]`：

```
[HookConfigurator] configuration complete, scriptVersion=2
```

**正常**：`scriptVersion=2`（v2 版本包含 POWERSHELL_SESSION_ID 检查）。

**异常 A**：`auto-config disabled` → 用户在设置中关闭了 Hook 自动配置。
- **修复**：设置 → Claude Code 集成 → 开启「自动配置 Hook 通知」

**异常 B**：`configuration failed` → settings.json 写入失败。
- **修复**：检查 `~/.claude/settings.json` 是否可写，文件格式是否合法

**异常 C**：scriptVersion=1 → Hook 脚本未更新到 v2。
- **修复**：删除 `~/.powershell/hooks/.script-version`，重启 PowerShell 触发重新生成

**额外检查**：验证 Hook 脚本文件存在且可执行：
```bash
ls -la ~/.powershell/hooks/powershell-hook.sh
cat ~/.powershell/hooks/powershell-hook.sh | head -5  # 应包含 POWERSHELL_SESSION_ID 检查
cat ~/.claude/settings.json | grep -A5 powershell-hook  # 应有4个事件类型的 Hook 条目
```

---

### 第 3 步：确认环境变量是否注入

在日志中搜索 `[TerminalPane]`：

```
[TerminalPane] startProcess: sessionId=XXXX, POWERSHELL_SESSION_ID injected
```

**正常**：每个 tab 创建时都有此日志。

**异常 A**：无此日志 → `TerminalPaneView` 未传入 `sessionId` 属性，代码版本过旧。
- **修复**：确认 `TerminalPaneView` 有 `sessionId: UUID` 属性，且在 `makeNSView` 中调用了 `Terminal.getEnvironmentVariables()` + `env.append("POWERSHELL_SESSION_ID=...")`

**异常 B**：旧 tab 无此日志（升级后）→ 旧 tab 在升级前创建，没有环境变量。
- **修复**：新建 tab 替代旧 tab（属预期行为）

**额外验证**：在 PowerShell 的终端中运行：
```bash
echo $POWERSHELL_SESSION_ID
```
应输出一个 UUID。如果为空，说明环境变量注入失败。

---

### 第 4 步：确认 Hook 事件是否到达服务器

在日志中搜索 `[HookServer] new connection` 和 `[HookServer] decoded event`：

```
[HookServer] new connection from ...
[HookServer] decoded event: SessionStart, session_id=xxx, type=nil, powershell_session_id=YYYY
```

**异常 A**：无 `new connection` → Claude Code 的 Hook 完全未触发。
- **修复**：
  1. 检查 `~/.claude/settings.json` 中是否有 `powershell-hook` 相关 Hook 条目
  2. 检查 `~/.powershell/hook-port` 文件中的端口号是否与 Hook 服务器监听端口一致
  3. 在其他终端运行 `claude` 检查是否能触发 Hook（如果其他终端也触发不了，问题在 Claude Code 侧）

**异常 B**：有 `new connection` 但无 `decoded event` → JSON 解码失败，检查 `[HookServer] JSON decode failed` 日志。
- **修复**：检查 Hook 脚本生成的 JSON 格式是否正确，特别是 sed fallback 路径可能产生非法 JSON

**异常 C**：`powershell_session_id=nil` → Hook 脚本 v1 在运行（未注入 POWERSHELL_SESSION_ID）。
- **修复**：确认 `~/.powershell/hooks/powershell-hook.sh` 是 v2 版本，检查 `.script-version` 文件

**异常 D**：有 `decoded event` 但 `powershell_session_id=nil` 且 POWERSHELL_SESSION_ID 应存在 → Hook 脚本中 JSON 注入逻辑失败。
- **修复**：检查 python3 是否可用（`which python3`），如果不可用则 sed fallback 可能有问题

---

### 第 5 步：确认 Session 映射是否正确

在日志中搜索 `[SessionManager]` 和 `[HookRouter]`：

```
[HookRouter] event=SessionStart, session_id=xxx, type=nil, psid=YYYY
[SessionManager] session start mapped via powershell_session_id: YYYY -> ZZZZ
```

**异常 A**：`session start mapped via activeSessionId (fallback)` → `powershell_session_id` 为 nil 或查不到映射。
- **修复**：
  1. 检查 `powershell_session_id` 是否被 Hook 脚本注入（回到第 4 步）
  2. 如果 psid 有值但查不到映射，说明该 session 已被删除或 UUID 不匹配

**异常 B**：`session end: no mapping found for claudeSessionId=xxx` → SessionStart 事件未正确映射。
- 这会导致后续 Notification/Stop 事件找不到目标 session
- **修复**：确保 SessionStart 事件在 SessionEnd 之前到达

**异常 C**：`[HookRouter] sending notification: targetSession=nil` → 所有查找方式都失败。
- **修复**：
  1. 确保 `activeSessionId` 不为 nil（至少有一个活跃 tab）
  2. 确保 `claudeSessionMap` 中有正确的映射（SessionStart 事件已处理）

---

### 第 6 步：确认通知是否发送到 FloatingPresenter

在日志中搜索 `[NotificationManager]` 和 `[FloatingPresenter]`：

```
[NotificationManager] send: title=PowerShell [终端 1], sessionId=XXXX
[FloatingPresenter] show: title=PowerShell [终端 1], sessionId=XXXX
[FloatingCenter] enqueue new: sessionId=XXXX
[FloatingPresenter] render: 1 presentation(s) on screen ...
```

**异常 A**：有 `[NotificationManager] send` 但无 `[FloatingPresenter] show` → FloatingPresenter 初始化异常。
- **修复**：检查 `NotificationManager` 的 `floatingPresenter` 是否为 `FloatingNotificationPanelPresenter` 实例

**异常 B**：有 `[FloatingPresenter] show` 但无 `[FloatingPresenter] render` → `render()` 中 `presentations()` 为空。
- **修复**：检查 `FloatingNotificationCenter.enqueue` 是否正确添加

**异常 C**：有 `render` 但 `no screen available` → 无可用屏幕（全屏模式下的边界情况）。
- **修复**：退出全屏模式测试

**异常 D**：有 `render` 且有 presentation 但弹窗不可见 → NSPanel 渲染问题。
- **修复**：
  1. 检查 `NSScreen.main` 是否正确返回当前屏幕
  2. 检查 `visibleFrame` 计算是否将弹窗放在了可见区域外
  3. 检查是否有其他窗口遮挡了 `.floating` level 的弹窗

---

## 无日志排查

如果 `~/.powershell/logs/debug.log` 不存在或为空：

1. **确认 PowerShell 版本**：旧版本可能没有 DebugLog 模块
2. **确认日志目录**：`ls -la ~/.powershell/logs/` 检查目录和文件是否存在
3. **手动验证 Hook 链路**：
   ```bash
   # 检查 Hook 脚本
   cat ~/.powershell/hooks/powershell-hook.sh

   # 检查端口文件
   cat ~/.powershell/hook-port

   # 检查 settings.json 中的 Hook 配置
   cat ~/.claude/settings.json | grep -B2 -A5 powershell-hook

   # 手动测试 Hook 服务器
   PORT=$(cat ~/.powershell/hook-port 2>/dev/null || echo "9786")
   curl -s -X POST "http://127.0.0.1:$PORT" \
     -H 'Content-Type: application/json' \
     -d '{"hook_event_name":"Notification","notification_type":"idle_prompt","session_id":"test","powershell_session_id":"test-session"}'

   # 检查环境变量
   echo $POWERSHELL_SESSION_ID
   ```

4. **检查 Claude Code Hook 是否触发**：
   - 在 PowerShell 终端运行 `claude`，观察是否有 `[HookServer] new connection` 日志
   - 如果没有，问题在 Claude Code 侧未触发 Hook

---

## 常见故障速查表

| 症状 | 最可能原因 | 修复 |
|------|-----------|------|
| 完全无通知 | Hook 服务器未启动 | 检查端口占用，重启 PowerShell |
| 完全无通知 | Hook 未配置 | 检查 settings.json，开启自动配置 |
| 完全无通知 | Hook 脚本 v2 过滤了所有事件 | 检查 `$POWERSHELL_SESSION_ID` 是否被注入 |
| 其他终端也触发通知 | Hook 脚本 v1（无环境变量检查） | 更新到 v2，删除 `.script-version` |
| 通知路由到错误 tab | powershell_session_id 缺失导致 fallback 到 activeSessionId | 确保 Hook 脚本 v2 正确注入 powershell_session_id |
| 升级后旧 tab 无通知 | 旧 tab 无 POWERSHELL_SESSION_ID 环境变量 | 新建 tab 替代（预期行为） |
| JSON 解码失败 | sed fallback 生成非法 JSON | 安装 python3，或检查 Hook 脚本 JSON 注入逻辑 |
| targetSession=nil | SessionStart 事件丢失或映射失败 | 检查 SessionStart 日志，确保在 Notification 事件之前到达 |
