# 全屏下顶部 Toolbar 常驻设计

## Context

当前实现已经把 `PowerShell` 文本从默认导航标题位置挪到了顶部 toolbar。与此同时，项目中原本存在一套全屏 hover 检测逻辑，会在进入全屏后自动隐藏窗口 toolbar，仅当鼠标移动到屏幕顶部时再暂时显示。

新的目标是：不仅 `PowerShell` 文本常驻，全屏状态下整条顶部 toolbar 都应保持可见，不再自动隐藏。这意味着 `Hide Sidebar`、`PowerShell` 以及其他顶部 toolbar 内容在全屏和非全屏下都采用一致的常驻显示行为。

## 目标

- 保持 `PowerShell` 在顶部 toolbar 中显示
- 取消全屏下 toolbar 自动隐藏
- 全屏下 `Hide Sidebar`、`PowerShell` 和其他 toolbar 项持续可见
- 不改动终端输入、会话管理、通知和 NL 建议逻辑

## 推荐方案

直接移除全屏下 toolbar 自动隐藏行为，保留现有 toolbar 内容定义：

1. 保留 `WindowChromeConfiguration` 和 `.toolbar` 中的 `Text("PowerShell")`
2. 删除或停用 `FullScreenHoverDetector` 相关显隐控制逻辑
3. 删除 `applyToolbarVisibility(window:hidden:)` 在全屏进入/hover 时对 `window.toolbar?.isVisible` 的切换
4. 保留全屏切换本身，不再根据鼠标位置改变 toolbar 可见性

这样处理后，toolbar 将遵循统一行为：无论普通窗口还是全屏，顶部栏都持续可见。

## 组件与影响范围

### 1. 受影响文件

仅修改 `Sources/PowerShell/App/PowerShellApp.swift`。

涉及区域：

- `FullScreenHoverDetector`
- `TerminalDetailView` 中与全屏 tracking 相关的调用点
- 当前 `.toolbar` 定义保持不变

### 2. 不改动内容

以下内容不在本次范围内：

- `SidebarView`
- `SessionManager`
- `TerminalPaneView`
- `NLViewModel`
- `HookNotificationServer`
- 通知、会话切换、终端行为

## 行为设计

### 普通窗口

- toolbar 始终可见
- 行为与当前非全屏状态一致

### 全屏窗口

- toolbar 始终可见
- 不再依赖鼠标移动到顶部触发显示
- 不再延迟隐藏

### PowerShell 标题

- 继续作为 toolbar 的 principal item 显示
- 与 `Hide Sidebar` 处于同一顶部栏
- 全屏时跟随 toolbar 持续显示

## 备选方案与取舍

### 方案 A（推荐）：彻底取消全屏自动隐藏

优点：

- 与用户目标完全一致
- 逻辑最直接
- 运行时状态更少，后续维护更简单

缺点：

- 会改变现有全屏下“沉浸式隐藏顶部栏”的交互

### 方案 B：仅让 `PowerShell` 单独常驻

优点：

- 对现有 toolbar 自动隐藏逻辑影响较小

缺点：

- 视觉不统一
- 实现更绕，需要额外叠加一层常驻 UI
- 不符合“整个顶部 toolbar 常驻”的明确目标

### 方案 C：调整 hover 阈值或隐藏延迟

优点：

- 改动较小

缺点：

- 不能保证常驻
- 只是缓解，不满足要求

## 测试与验证

### 手动验证

1. 普通窗口下确认 toolbar 持续可见
2. 普通窗口下确认 `PowerShell` 仍在 `Hide Sidebar` 同一栏
3. 进入全屏后确认 toolbar 不会自动消失
4. 全屏下移动鼠标离开顶部，确认 toolbar 仍可见
5. 全屏下确认 `Hide Sidebar` 与 `PowerShell` 都持续可见
6. 验证终端输入、会话切换、NL 建议浮层不受影响

### 构建验证

- 运行 `swift build`
- 如环境允许，运行应用做 UI smoke test

## 非目标

以下内容不在本次范围内：

- 自定义新的浮动标题栏 UI
- 增加全屏专用标题样式
- 修改 session 标题栏内容
- 修改 toolbar 内其他按钮布局
- 调整系统全屏机制本身
