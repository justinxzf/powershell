# 分屏顶部栏样式统一设计

## Context

当前分屏实现里，左侧 pane 会渲染完整顶部栏，但右侧 secondary pane 在 `Sources/PowerShell/App/PowerShellApp.swift` 中通过 `if !isSplitSecondary` 直接隐藏了顶部栏。这导致两边高度不一致、样式不一致，且右侧无法稳定展示当前地址。

这次只处理分屏顶部栏的展示一致性，不改动分屏比例、拖拽分屏、取消分屏、终端进程生命周期或 sidebar 交互。

## 目标

- 左右分栏顶部区域高度一致
- 左右分栏顶部区域视觉结构一致
- 右侧分栏也展示当前地址
- 保持现有分屏布局、拖拽与取消分屏逻辑不变
- 不重建任何 PTY / TerminalPaneView

## 推荐方案

采用“左右两栏都渲染同一套 header”的方式，直接收敛现有 `TerminalDetailView` 的标题栏逻辑，而不是新增共享顶栏或重做分屏容器。

具体做法：

1. 移除 `TerminalDetailView` 中“secondary pane 不显示标题栏”的分支，让左右 pane 都显示 header
2. 把 header 主文本统一收敛为“当前目录优先，其次 terminal title，最后 session name”
3. 保留状态点、shell 标签、背景、边框、padding 的现有风格，使两边观感完全一致
4. 仅在 primary pane 继续保留分屏控制区（例如取消分屏或 secondary 信息），避免两边都出现重复控制

这样可以满足“样式一样 + 高度一样 + 右侧显示当前地址”，同时把改动集中在单个视图组件内，避免扩大影响范围。

## 组件设计

### 1. Header 内容规则

每个 pane 的 header 统一为三段：

- 左侧状态点：沿用当前活跃状态颜色逻辑
- 中间主文本：
  - 优先显示 `session.currentDirectory`
  - 如果目录暂未同步，再回退到 `terminalTitle`
  - 如果两者都没有，再显示 `session.name`
- 右侧 shell 标签：沿用现有 `session.shellType.displayName`

这样右侧 pane 可以稳定显示当前地址，同时不会在目录还没同步前出现空白标题。

### 2. Primary / Secondary 的差异

为了让视觉统一但避免操作重复：

- **Primary pane**：显示完整 header，并继续显示现有分屏控制区
- **Secondary pane**：显示同样的 header 骨架与信息，但不显示“再分屏”菜单，也不额外放重复的取消分屏按钮

换句话说，两边的基础样式完全一致，但只有 primary 保留分屏控制入口。这样既满足 UI 一致性，也避免右侧 header 过于拥挤。

### 3. 数据来源

不新增新的状态模型，继续复用已有数据：

- `Session.currentDirectory`：由现有 `onDirectoryChanged` 流程更新
- `terminalTitle`：由现有 `TerminalPaneView.onTitleChanged` 更新
- `Session.shellType`：现有字段
- `Session.isActive`：现有状态点逻辑

因此本次不需要修改 `SessionManager` 的分屏数据结构，也不需要调整 `TerminalPaneView` 生命周期。

## 影响范围

### 修改文件

- `Sources/PowerShell/App/PowerShellApp.swift`
  - 调整 `TerminalDetailView` header 渲染逻辑
  - 抽出 header 标题文本的优先级逻辑
  - 让 secondary pane 也渲染 header

### 不修改文件

- `Sources/PowerShell/ViewModels/SessionManager.swift`
- `Sources/PowerShell/Views/SidebarView.swift`
- `Tests/PowerShellTests/SessionManagerSplitTests.swift`
- 分屏拖拽和分割线相关逻辑

## 数据流与交互

本次不改变业务数据流，只改变 UI 呈现：

1. 终端运行后继续通过现有回调更新 `terminalTitle` 和 `currentDirectory`
2. `TerminalDetailView` 在每个 pane 顶部统一渲染 header
3. header 文本优先显示当前目录，确保左右两栏都能表达“当前在哪个地址”
4. primary pane 保留分屏操作入口，secondary pane 只负责展示，不新增交互

## 备选方案与取舍

### 方案 A（推荐）：两栏各自渲染一致 header

优点：

- 最符合当前需求
- 改动集中
- 不影响现有分屏布局结构
- 右侧可自然展示当前地址

缺点：

- 会让右侧多出一条 header，占用少量垂直空间

### 方案 B：右侧补一个简化 header

优点：

- 改动较小
- 信息密度可控

缺点：

- 仍然不是完全一致的视觉结构
- 不符合已确认的方向

### 方案 C：改成共享顶栏展示两边信息

优点：

- 信息集中
- 最容易做全局对齐

缺点：

- 需要重构分屏容器与交互表达
- 明显超出这次范围

## 测试与验证

### 手动验证

1. 进入分屏模式，确认左右两栏顶部高度一致
2. 确认左右两栏背景、边框、padding、状态点、shell 标签样式一致
3. 确认右侧分栏能展示当前地址
4. 在目录切换后确认左右 header 文本会随之更新
5. 确认 primary pane 的分屏控制仍可使用
6. 确认 secondary pane 不会出现重复控制按钮
7. 拖动分割线后确认顶部栏仍保持对齐
8. 退出分屏后确认单栏展示保持原有行为

### 构建验证

- 运行 `swift build`
- 如环境允许，启动应用手动检查分屏 UI

## 非目标

以下内容不在本次范围内：

- 调整分屏比例算法
- 修改分屏拖拽交互
- 新增多于 2 个 pane 的布局能力
- 重构 header 为独立共享组件以外的更大范围 UI 清理
- 修改终端 title / cwd 的底层采集逻辑
