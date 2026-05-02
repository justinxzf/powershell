---
name: toolbar-split-spacing-design
description: Stabilize toolbar spacing by moving split controls into a structured trailing toolbar group while preserving the centered PowerShell title.
type: project
---

# Toolbar 分屏操作区间距稳定化设计

## 背景

当前窗口最上方的系统 toolbar 中，左侧 sidebar 按钮、中间 `PowerShell` 标题、右侧分屏相关操作在不同状态下会出现明显的视觉距离波动。尤其是右侧分屏控件数量和内容变化时，用户会感受到“忽远忽近”的不稳定感。

本次优化目标不是改变交互语义，也不是把控件迁移到终端内容区，而是在保留系统 toolbar 结构的前提下，让顶部区域的视觉分布更稳定、更协调。

## 目标

- 保留系统 toolbar 作为顶部控制承载区域
- 保留左侧 sidebar 按钮
- 保留中间 `PowerShell` 标题
- 右侧分屏操作区仅在“有分屏 / 可操作”时显示
- 分屏操作区显示时，内部间距、背景形态、图标尺寸保持稳定
- 尽量减少因状态变化导致的 toolbar 视觉跳动

## 非目标

- 不改变分屏能力本身
- 不新增交互入口或新功能
- 不把分屏控件移动到 `TerminalDetailView` 头部区域
- 不重做 sidebar、标题文案或窗口 chrome 风格

## 当前实现观察

- 系统 toolbar 标题定义在 `Sources/PowerShell/App/PowerShellApp.swift:115`
- 每个终端 pane 自己还带有一个 header，定义在 `Sources/PowerShell/App/PowerShellApp.swift:357`
- 分屏相关 accessory 当前来自插件 `SplitPlugin` 的 `headerAccessoryView`，定义在 `Sources/PowerShell/Plugins/SplitPlugin.swift:162`

当前分屏操作实际挂在终端 pane header 内，而用户反馈的问题集中在窗口最上方 toolbar 的视觉距离不稳定。因此本次设计需要把“稳定化”重点放在系统 toolbar 这一层，而不是继续依赖 pane header 的自然布局。

## 方案对比

### 方案 1：toolbar 三段式稳定布局（采用）

左侧保留 sidebar 按钮，中间保留 `PowerShell` 标题，右侧引入稳定的分屏操作组容器。该容器只在有内容时显示，但一旦显示出来，内部排布固定，形成统一胶囊式视觉块。

优点：
- 最符合用户当前偏好
- 保持现有信息架构
- 改动聚焦在顶部布局承载方式，风险可控

缺点：
- 仍需适配 macOS toolbar 自身的自适应布局规则

### 方案 2：右侧统一为单菜单入口（未采用）

优点是最稳定，缺点是功能显性降低、交互层级更深。

### 方案 3：仅微调现有间距（未采用）

优点是改动最小，缺点是只能缓解，难以根治状态切换时的视觉漂移。

## 采用设计

### 1. 顶部结构

窗口最上方系统 toolbar 采用明确的三段式语义：

- 左：sidebar 按钮
- 中：`PowerShell` 标题
- 右：分屏操作组

其中右侧分屏操作组不再依赖每个 pane header 自由撑开后的结果，而是作为一个独立的 toolbar 表达单元来布局。

### 2. 分屏操作组表现

右侧操作组遵循以下视觉规则：

- 组内图标尺寸统一
- 组内按钮间距固定
- 有辅助文本时，文本与按钮使用统一 gap
- 外层使用一致的胶囊式背景或等效视觉分组手法
- 不同状态下尽量保持组内基线与高度一致

这样即使从“单窗格可分屏”切换到“已分屏摘要 + 取消分屏”，用户看到的仍然是同一块稳定区域，只是内容更新，而不是布局突然被拉开。

### 3. 显隐策略

右侧操作组仅在以下情况显示：

- 当前上下文存在分屏相关可操作项
- 或当前已经处于分屏态，需要展示摘要 / 取消分屏 / 扩展四宫格等操作

在完全无相关操作时，整组不显示，不引入永久占位。

### 4. 与现有 pane header 的关系

当前 `TerminalDetailView` 头部仍保留会话标题和 shell 标签。但分屏操作不应继续主要依赖 pane header 的 accessory 去承担顶部稳定布局职责。

因此建议：

- 将分屏操作的主要入口迁移到系统 toolbar 的右侧稳定分组中
- pane header 如需保留辅助信息，应避免与 toolbar 中的分屏操作形成重复或竞争
- 若迁移后 pane header 的 accessory 已无必要，可移除或弱化

### 5. 插件边界

按仓库规则，优先走插件能力而非直接侵入核心结构。本次应优先考虑：

- 扩展 `PowerShellPlugin`，让插件能够提供 toolbar trailing 内容，而不是只提供 pane header accessory
- `SplitPlugin` 继续负责分屏状态与动作生成
- `PowerShellApp` 只负责把插件提供的 toolbar 内容渲染到合适区域

如果现有插件协议无法表达 toolbar 右侧内容，则新增一个可选的 toolbar API，默认 no-op。

## 数据流与职责

### `SplitPlugin`
负责：
- 判断当前是否可分屏
- 判断当前处于哪种分屏状态
- 生成对应的 toolbar 右侧内容
- 响应分屏、取消分屏、扩展四宫格等操作

### `PluginManager`
负责：
- 聚合插件提供的 toolbar trailing 视图
- 向根视图暴露第一个可用的 toolbar 视图

### `RootContentView`
负责：
- 在系统 toolbar 中渲染标题与右侧分屏操作组
- 保持左中右结构稳定

## 测试与验证

需要重点验证：

1. 单 session、无可分屏对象时，toolbar 显示自然，无多余占位
2. 有其他 session 可分屏时，右侧操作组出现，内部间距稳定
3. 已进入水平 / 垂直分屏后，摘要与取消按钮显示稳定
4. 扩展四宫格选择流程中，右侧操作组不会出现明显跳动
5. 窗口宽度变化、全屏切换后，toolbar 排布仍然协调
6. 中文 UI 文案和图标在窄宽度下不互相挤压

## 风险与控制

主要风险：
- macOS `ToolbarItem` 在不同窗口宽度下会自动重排
- 从 pane header 迁移分屏控件到 toolbar 后，可能与现有 pane header 信息重复
- 如果 toolbar API 设计不当，可能破坏插件优先原则

控制方式：
- 先做最小可用的 toolbar trailing 插件扩展
- 保持 `SplitPlugin` 负责逻辑，核心只增加承载接口
- 使用本地运行手工验证真实窗口行为，而不是只看静态代码

## 实施范围

预期会涉及：

- `Sources/PowerShell/Plugins/PowerShellPlugin.swift`
- `Sources/PowerShell/Plugins/PluginManager.swift`
- `Sources/PowerShell/Plugins/SplitPlugin.swift`
- `Sources/PowerShell/App/PowerShellApp.swift`

尽量避免不必要改动其他核心文件。
