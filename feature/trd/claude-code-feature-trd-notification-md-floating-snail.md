# Hook 自动配置方案：PowerShell 内闭环完成通知配置

## Context

当前 PowerShell 通知系统依赖 Claude Code Hooks，用户必须手动完成两步配置：
1. 创建 `~/.claude/hooks/powershell-hook.sh` 脚本
2. 修改 `~/.claude/settings.json` 添加 hooks 配置

分发给别人用时，每个人都要手动做这两步，体验差。**目标：用户安装 PowerShell 即可，无需手动改任何配置文件。**

> 本质约束：Claude Code 只从 `~/.claude/settings.json` 读取 hooks 配置，无法绕过。因此"不改配置文件"在严格意义上不可能，但可以通过**应用自动配置**让用户无感。

---

## 方案：HookConfigurator 自动配置服务

PowerShell 启动时自动完成 hooks 配置，用户无需任何手动操作。

### 核心设计

1. **Hook 脚本迁移到 `~/.powershell/hooks/`**（而非 `~/.claude/hooks/`）
   - 所有 PowerShell 文件统一在 `~/.powershell/` 下，便于管理和清理
   - settings.json 中的 command 路径改为 `~/.powershell/hooks/powershell-hook.sh`

2. **新增 `HookConfigurator` 服务**，启动时自动：
   - 创建 `~/.powershell/hooks/powershell-hook.sh`（含执行权限）
   - 安全合并 hooks 配置到 `~/.claude/settings.json`（保留用户已有配置）

3. **幂等设计**：每次启动都检查，只在需要时写入
   - 脚本通过版本文件 `~/.powershell/hooks/.script-version` 判断是否需要更新
   - settings.json 通过 marker 字符串 `"powershell-hook"` 检测已有配置

4. **Settings UI 提供开关**：用户可在设置中关闭自动配置，关闭时自动清理

---

## 文件变更

| 文件 | 操作 | 说明 |
|------|------|------|
| `Sources/PowerShell/Services/HookConfigurator.swift` | **新建** | 自动配置服务核心实现 |
| `Sources/PowerShell/App/PowerShellApp.swift` | **修改** | 在 `.task` 中添加一行调用 |
| `Sources/PowerShell/Views/SettingsView.swift` | **修改** | 添加"Claude Code 集成"开关 |
| `feature/trd/notification.md` | **修改** | 更新使用步骤为自动配置 |

---

## 详细实现

### 1. HookConfigurator（新建 ~150 行）

```
Sources/PowerShell/Services/HookConfigurator.swift
```

**关键属性：**
- `hookEvents = ["SessionStart", "SessionEnd", "Notification", "Stop"]`
- `hookMarker = "powershell-hook"` — 用于从 settings.json 中识别 PowerShell 的 hook
- `hookScriptVersion = 1` — 脚本版本号，升级时递增
- `hookCommandPath = "~/.powershell/hooks/powershell-hook.sh"` — settings.json 中的路径

**核心方法：**

| 方法 | 说明 |
|------|------|
| `configureIfNeeded()` | 入口，检查开关 → 写脚本 → 合并 settings.json |
| `ensureHookScript()` | 创建目录 + 写脚本 + chmod +x + 写版本文件 |
| `ensureHooksInSettings()` | 读 settings.json → 检查/添加 PowerShell hooks → 写回 |
| `removeHooksFromSettings()` | 精确移除 PowerShell hook 条目，保留其他工具的 hooks |
| `cleanup()` | 关闭开关时调用：移除 settings.json hooks + 删除脚本 |
| `setAutoConfigEnabled(_:)` | 开关切换，关闭时 cleanup，开启时 configure |

**settings.json 安全合并策略：**

1. 读取为 `[String: Any]` 字典（文件不存在则返回空字典）
2. 遍历四个 hook 事件，对每个事件：
   - 扫描已有 hook 条目，查找 `command` 包含 `"powershell-hook"` 的条目
   - 找到 → 更新 command 路径（处理旧路径迁移）
   - 没找到 → 追加新条目
3. 写回时使用 `JSONSerialization.data(withJSONObject:options:[.sortedKeys, .prettyPrinted])`
4. 使用 atomic write 防止写入中断

**错误处理原则：** 所有错误仅记录日志，绝不 crash。配置失败则本次启动通知不可用，重启后重试。

### 2. PowerShellApp.swift 集成（修改 1 行）

在 `RootContentView` 的 `.task` 修饰器中，`HookNotificationServer.shared.start()` **之前**添加：

```swift
// 第 222 行之后，第 223 行之前
HookConfigurator.shared.configureIfNeeded()
```

### 3. SettingsView.swift 添加开关（修改 ~15 行）

在"外观"Section（第 85-96 行）之后、保存按钮 Section（第 98 行）之前，添加：

```swift
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
```

调整 frame height：默认模式 +50pt → 370，自定义模式 +50pt → 530。

### 4. 旧用户迁移

- `ensureHookScript()` 在新位置创建脚本
- `ensureHooksInSettings()` 检测到旧路径 `~/.claude/hooks/powershell-hook.sh` → 更新为 `~/.powershell/hooks/powershell-hook.sh`
- `~/.claude/hooks/` 下的旧脚本保留（无害，可手动删除）

---

## 验证方式

1. 删除 `~/.claude/settings.json` 中的 hooks 配置和 `~/.powershell/hooks/` 目录
2. 启动 PowerShell
3. 检查 `~/.powershell/hooks/powershell-hook.sh` 已创建且有执行权限
4. 检查 `~/.claude/settings.json` 中已包含 PowerShell hooks
5. 在终端运行 `claude`，验证通知正常工作
6. 在设置中关闭开关，验证 hooks 被移除
7. 重新打开开关，验证 hooks 被重新配置
8. 测试已有其他 hooks 的 settings.json，确认不被覆盖
