# 自定义标题栏 PowerShell 文本位置调整设计

## Context

当前应用在 `NavigationSplitView` 详情区域使用了默认的 `navigationTitle("PowerShell")`，因此 `PowerShell` 文本显示在系统默认标题位置。目标是移除这个默认标题显示方式，改为在窗口顶部工具栏区域增加一个固定文本，让它出现在 `Hide Sidebar` 同一栏中。

本次仅调整标题栏中文本的位置，不引入动态标题、不改动会话管理逻辑，也不改变现有全屏标题栏显示/隐藏机制。

## 目标

- 去掉默认标题栏前面的 `PowerShell` 文本
- 在顶部工具栏同一栏中固定显示 `PowerShell`
- 保持现有窗口布局和终端区域行为不变
- 保持全屏模式下标题栏跟随现有逻辑显示/隐藏

## 推荐方案

采用 SwiftUI toolbar 自定义标题文案：

1. 删除 `Sources/PowerShell/App/PowerShellApp.swift` 中详情视图上的 `navigationTitle("PowerShell")`
2. 在同一视图层级增加 `.toolbar`，插入一个固定的 `Text("PowerShell")`
3. 使用顶部工具栏的主区域放置该文本，使其和 `Hide Sidebar` 处于同一栏视觉层级
4. 不修改 `FullScreenHoverDetector` 和 `setupFullScreenTracking()` 的逻辑，让新增文本自然跟随工具栏显隐

## 组件与影响范围

### 1. 标题文本来源

- 文案固定为 `PowerShell`
- 不依赖当前 session、目录或终端状态
- 不需要新增状态变量或 ViewModel 字段

### 2. 视图改动范围

仅修改 `Sources/PowerShell/App/PowerShellApp.swift`：

- 移除默认 `navigationTitle`
- 增加一个 toolbar item 展示固定标题文本

不需要改动：

- `SessionManager`
- `TerminalDetailView`
- `SidebarView`
- `Views/TerminalView.swift`
- 任何 LLM / NL 相关逻辑

### 3. 全屏行为

现有实现中，工具栏显示与否由 `FullScreenHoverDetector` 控制。新加入的标题文本属于工具栏内容，因此：

- 非全屏：始终可见
- 全屏且鼠标移到顶部：可见
- 全屏且工具栏自动隐藏后：一并隐藏

这样可保持当前交互一致性，不需要为文本单独维护显隐状态。

## 数据流与交互

本次变更不影响业务数据流，仅影响窗口顶部 UI 呈现：

- App 启动后渲染 `NavigationSplitView`
- 详情区域不再提供默认导航标题
- 工具栏区域提供固定文本 `PowerShell`
- 全屏切换时仍由原有窗口工具栏逻辑控制显示效果

## 备选方案与取舍

### 方案 A（推荐）：toolbar 固定文本

优点：

- 改动最小
- 位置最接近目标效果
- 易于维护，不新增状态耦合

缺点：

- 文本位置受系统工具栏布局规则影响，不能像完全自定义 title bar 那样任意布局

### 方案 B：保留系统 `navigationTitle`

优点：

- 实现最少

缺点：

- 无法稳定放到 `Hide Sidebar` 同栏
- 不满足这次视觉目标

### 方案 C：完整自定义 title bar 容器

优点：

- 控制力最高

缺点：

- 明显超出需求
- 会增加窗口标题栏与工具栏行为维护成本

## 测试与验证

### 手动验证

1. 启动应用，确认默认标题位置不再显示 `PowerShell`
2. 确认 `PowerShell` 文本出现在 `Hide Sidebar` 同一栏
3. 切换不同 session，确认该文本始终固定不变
4. 进入全屏，鼠标移到顶部时确认该文本随工具栏一起出现
5. 全屏下移开鼠标，确认该文本随工具栏一起隐藏
6. 验证终端输入、侧边栏切换、NL 建议浮层不受影响

### 构建验证

- 运行 `swift build`
- 如环境允许，运行应用进行界面确认

## 非目标

以下内容不在本次范围内：

- 显示当前 session 名称
- 显示当前目录路径
- 增加动态副标题
- 重构现有全屏标题栏隐藏逻辑
- 调整其他 toolbar 按钮布局
