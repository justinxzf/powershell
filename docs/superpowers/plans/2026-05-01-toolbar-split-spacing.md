# Toolbar 分屏操作区间距稳定化 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把分屏相关操作从 pane header 迁移到系统 toolbar 的右侧稳定分组中，保留中间 `PowerShell` 标题，并消除顶部控件在不同状态下“忽远忽近”的视觉波动。

**Architecture:** 先把 `SplitPlugin` 的 toolbar 决策抽成可测试的纯状态模型 `SplitToolbarPresentation`，用单元测试锁定“隐藏 / 可分屏按钮 / 分屏摘要 / 仅取消分屏”几种状态。然后扩展插件协议和 `PluginManager`，让插件直接提供 toolbar trailing view；`RootContentView` 负责把这个 view 渲染到系统 toolbar，`TerminalDetailView` 则去掉旧的 header accessory 承载，只保留标题与 shell 标签。

**Tech Stack:** Swift 6.0, SwiftUI (macOS 14+), XCTest, Swift Package Manager

---

## 文件清单

| 文件 | 操作 | 职责 |
|---|---|---|
| `Sources/PowerShell/Plugins/SplitPlugin.swift` | 修改 | 新增 `SplitToolbarPresentation` 与 `toolbarPresentation(...)`，提供右侧 toolbar accessory view，并关闭旧的 pane header accessory 输出 |
| `Sources/PowerShell/Plugins/PowerShellPlugin.swift` | 修改 | 为插件系统新增 toolbar trailing view 可选接口 |
| `Sources/PowerShell/Plugins/PluginManager.swift` | 修改 | 聚合插件提供的 toolbar trailing view |
| `Sources/PowerShell/App/PowerShellApp.swift` | 修改 | 在 `RootContentView` 的系统 toolbar 渲染右侧分组；移除 `TerminalDetailView` 的 `headerAccessoryView` 依赖；把标题 placement 调整为更符合“三段式”的 placement |
| `Tests/PowerShellTests/SplitPluginToolbarPresentationTests.swift` | 新建 | 锁定分屏 toolbar 状态决策逻辑 |
| `Tests/PowerShellTests/PowerShellAppTitleBarTests.swift` | 修改 | 锁定标题 placement 和 toolbar trailing view 的基本可用性 |

---

## Task 1: 用测试锁定 SplitPlugin 的 toolbar 状态决策

**Files:**
- Create: `Tests/PowerShellTests/SplitPluginToolbarPresentationTests.swift`
- Modify: `Sources/PowerShell/Plugins/SplitPlugin.swift`

- [ ] **Step 1: 新建失败测试，覆盖隐藏 / 可分屏 / 分屏摘要 / grid 控制状态**

```swift
// Tests/PowerShellTests/SplitPluginToolbarPresentationTests.swift
import XCTest
@testable import PowerShell

@MainActor
final class SplitPluginToolbarPresentationTests: XCTestCase {
    private let session1 = Session(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        name: "终端 1",
        shellType: .zsh,
        isActive: true
    )

    private let session2 = Session(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
        name: "终端 2",
        shellType: .zsh,
        isActive: false
    )

    private let session3 = Session(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
        name: "终端 3",
        shellType: .bash,
        isActive: false
    )

    private let session4 = Session(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
        name: "终端 4",
        shellType: .bash,
        isActive: false
    )

    func testToolbarPresentationIsHiddenWhenThereIsNoSplitAndNoOtherSessions() {
        let plugin = SplitPlugin()

        let presentation = plugin.toolbarPresentation(
            activeSession: session1,
            allSessions: [session1]
        )

        XCTAssertEqual(presentation, .hidden)
    }

    func testToolbarPresentationShowsSplitActionsWhenOtherSessionsExist() {
        let plugin = SplitPlugin()

        let presentation = plugin.toolbarPresentation(
            activeSession: session1,
            allSessions: [session1, session2]
        )

        XCTAssertEqual(
            presentation,
            .splitActions(targets: [
                SplitToolbarPresentation.Target(id: session2.id, name: "终端 2")
            ])
        )
    }

    func testToolbarPresentationShowsSplitSummaryForPrimaryPane() {
        let plugin = SplitPlugin()
        plugin.splitHorizontal(left: session1.id, right: session2.id)

        let presentation = plugin.toolbarPresentation(
            activeSession: session1,
            allSessions: [session1, session2, session3, session4]
        )

        XCTAssertEqual(
            presentation,
            .splitSummary(secondaryName: "终端 2", showsGridExpand: true)
        )
    }

    func testToolbarPresentationShowsUnsplitOnlyForGridControlPane() {
        let plugin = SplitPlugin()
        plugin.splitGrid(
            topLeft: session1.id,
            topRight: session2.id,
            bottomLeft: session3.id,
            bottomRight: session4.id
        )

        let presentation = plugin.toolbarPresentation(
            activeSession: session1,
            allSessions: [session1, session2, session3, session4]
        )

        XCTAssertEqual(presentation, .unsplitOnly)
    }
}
```

- [ ] **Step 2: 运行测试，确认按预期失败**

Run: `swift test --filter SplitPluginToolbarPresentationTests`

Expected: FAIL，提示 `SplitPlugin` 上不存在 `toolbarPresentation`，或 `SplitToolbarPresentation` 未定义。

- [ ] **Step 3: 在 `Sources/PowerShell/Plugins/SplitPlugin.swift` 中新增可测试状态模型与决策方法**

把下面代码加在 `// MARK: - SplitPlugin` 之前和 `SplitPlugin` 类内部：

```swift
enum SplitToolbarPresentation: Equatable {
    struct Target: Equatable {
        let id: UUID
        let name: String
    }

    case hidden
    case splitActions(targets: [Target])
    case splitSummary(secondaryName: String, showsGridExpand: Bool)
    case unsplitOnly
}

@Observable
@MainActor
final class SplitPlugin: PowerShellPlugin {
    // ... existing properties ...

    func toolbarPresentation(activeSession: Session, allSessions: [Session]) -> SplitToolbarPresentation {
        switch role(of: activeSession.id) {
        case .singlePane:
            let targets = allSessions
                .filter { $0.id != activeSession.id }
                .map { SplitToolbarPresentation.Target(id: $0.id, name: $0.name) }
            return targets.isEmpty ? .hidden : .splitActions(targets: targets)

        case .hPrimary(let secondaryId), .vPrimary(let secondaryId):
            let secondaryName = allSessions.first(where: { $0.id == secondaryId })?.name ?? ""
            let available = availableSessions(excluding: activeSession.id, allSessions: allSessions)
            return .splitSummary(
                secondaryName: secondaryName,
                showsGridExpand: available.count >= 2
            )

        case .gridControl:
            return .unsplitOnly

        case .secondary:
            return .hidden
        }
    }

    private func availableSessions(excluding sessionId: UUID, allSessions: [Session]) -> [Session] {
        let excluded: Set<UUID> = {
            var ids: Set<UUID> = [sessionId]
            switch splitLayout {
            case .horizontal(let left, let right):
                ids.formUnion([left, right])
            case .vertical(let top, let bottom):
                ids.formUnion([top, bottom])
            case .grid(let topLeft, let topRight, let bottomLeft, let bottomRight):
                ids.formUnion([topLeft, topRight, bottomLeft, bottomRight])
            case .none:
                break
            }
            return ids
        }()

        return allSessions.filter { !excluded.contains($0.id) }
    }
}
```

- [ ] **Step 4: 让 `SplitHeaderAccessoryView` 复用新的 `availableSessions(excluding:allSessions:)`，避免重复逻辑**

把 `SplitHeaderAccessoryView` 里的 `availableSessions` 计算属性替换成：

```swift
private var availableSessions: [Session] {
    plugin.availableSessions(excluding: session.id, allSessions: allSessions)
}
```

并把 `availableSessions(excluding:allSessions:)` 的访问级别从 `private` 调整为文件内可访问：

```swift
func availableSessions(excluding sessionId: UUID, allSessions: [Session]) -> [Session] {
    // implementation unchanged
}
```

- [ ] **Step 5: 运行测试，确认状态决策通过**

Run: `swift test --filter SplitPluginToolbarPresentationTests`

Expected: PASS，4 个 `SplitPluginToolbarPresentationTests` 全部通过。

- [ ] **Step 6: 提交状态模型和测试**

```bash
git add Sources/PowerShell/Plugins/SplitPlugin.swift \
        Tests/PowerShellTests/SplitPluginToolbarPresentationTests.swift
git commit -m "test: lock split toolbar presentation states"
```

---

## Task 2: 扩展插件协议并实现右侧 toolbar 稳定分组

**Files:**
- Modify: `Sources/PowerShell/Plugins/PowerShellPlugin.swift`
- Modify: `Sources/PowerShell/Plugins/PluginManager.swift`
- Modify: `Sources/PowerShell/Plugins/SplitPlugin.swift`
- Modify: `Tests/PowerShellTests/PowerShellAppTitleBarTests.swift`

- [ ] **Step 1: 先补失败测试，锁定标题 placement 和 toolbar trailing view 的基本行为**

在 `Tests/PowerShellTests/PowerShellAppTitleBarTests.swift` 里追加两个测试：

```swift
@MainActor
func testAppChromeConfigurationCentersToolbarTitle() {
    let chrome = WindowChromeConfiguration.app

    XCTAssertEqual(chrome.toolbarTitle, "PowerShell")
    XCTAssertEqual(chrome.titlePlacement, .principal)
}

@MainActor
func testSplitPluginReturnsToolbarTrailingViewOnlyWhenPresentationIsVisible() {
    let plugin = SplitPlugin()
    let primary = Session(
        id: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
        name: "终端 1",
        shellType: .zsh,
        isActive: true
    )
    let secondary = Session(
        id: UUID(uuidString: "10000000-0000-0000-0000-000000000002")!,
        name: "终端 2",
        shellType: .zsh,
        isActive: false
    )

    XCTAssertNil(
        plugin.toolbarTrailingView(activeSession: primary, allSessions: [primary])
    )

    XCTAssertNotNil(
        plugin.toolbarTrailingView(activeSession: primary, allSessions: [primary, secondary])
    )
}
```

- [ ] **Step 2: 运行测试，确认按预期失败**

Run: `swift test --filter PowerShellAppTitleBarTests`

Expected: FAIL，提示 `titlePlacement` 不是 `.principal`，以及 `toolbarTrailingView(activeSession:allSessions:)` 尚未定义。

- [ ] **Step 3: 在 `PowerShellPlugin` 协议中新增 toolbar trailing view 接口**

把 `Sources/PowerShell/Plugins/PowerShellPlugin.swift` 改成下面这样：

```swift
@MainActor
protocol PowerShellPlugin: AnyObject {
    var pluginId: String { get }

    func setup()
    func handleHookEvent(_ event: HookEvent, sessionManager: SessionManager)

    func terminalCreated(_ terminal: InterceptingTerminalView, session: Session)
    func directoryChanged(to directory: String?, session: Session)
    func processTerminated(session: Session)
    func terminalFocused(session: Session)

    @ViewBuilder
    func settingsSection() -> (any View)?

    var skillsDirectoryPath: String? { get }

    func sessionDidActivate(sessionId: UUID)
    func sessionWillDelete(sessionId: UUID)
    func overlayView(size: CGSize) -> AnyView?
    func headerAccessoryView(for session: Session, allSessions: [Session]) -> AnyView?
    func toolbarTrailingView(activeSession: Session, allSessions: [Session]) -> AnyView?
}

extension PowerShellPlugin {
    func handleHookEvent(_ event: HookEvent, sessionManager: SessionManager) {}
    func terminalCreated(_ terminal: InterceptingTerminalView, session: Session) {}
    func directoryChanged(to directory: String?, session: Session) {}
    func processTerminated(session: Session) {}
    func terminalFocused(session: Session) {}
    func settingsSection() -> (any View)? { nil }
    var skillsDirectoryPath: String? { nil }
    func sessionDidActivate(sessionId: UUID) {}
    func sessionWillDelete(sessionId: UUID) {}
    func overlayView(size: CGSize) -> AnyView? { nil }
    func headerAccessoryView(for session: Session, allSessions: [Session]) -> AnyView? { nil }
    func toolbarTrailingView(activeSession: Session, allSessions: [Session]) -> AnyView? { nil }
}
```

- [ ] **Step 4: 在 `PluginManager` 中增加 toolbar trailing 聚合方法**

在 `Sources/PowerShell/Plugins/PluginManager.swift` 里新增：

```swift
func firstToolbarTrailingView(activeSession: Session?, allSessions: [Session]) -> AnyView? {
    guard let activeSession else { return nil }
    return plugins.lazy
        .compactMap { $0.toolbarTrailingView(activeSession: activeSession, allSessions: allSessions) }
        .first
}
```

- [ ] **Step 5: 在 `SplitPlugin.swift` 中实现稳定胶囊样式的 toolbar trailing view**

在 `SplitPlugin` 类里新增实现，并在文件底部追加 `SplitToolbarAccessoryView`：

```swift
func toolbarTrailingView(activeSession: Session, allSessions: [Session]) -> AnyView? {
    guard toolbarPresentation(activeSession: activeSession, allSessions: allSessions) != .hidden else {
        return nil
    }

    return AnyView(
        SplitToolbarAccessoryView(
            plugin: self,
            activeSession: activeSession,
            allSessions: allSessions
        )
    )
}

func headerAccessoryView(for session: Session, allSessions: [Session]) -> AnyView? {
    nil
}
```

```swift
struct SplitToolbarAccessoryView: View {
    let plugin: SplitPlugin
    let activeSession: Session
    let allSessions: [Session]

    private var presentation: SplitToolbarPresentation {
        plugin.toolbarPresentation(activeSession: activeSession, allSessions: allSessions)
    }

    var body: some View {
        switch presentation {
        case .hidden:
            EmptyView()

        default:
            HStack(spacing: 8) {
                SplitHeaderAccessoryView(
                    plugin: plugin,
                    session: activeSession,
                    allSessions: allSessions
                )
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.quaternary, in: Capsule())
        }
    }
}
```

这样先复用已经存在的 `SplitHeaderAccessoryView` 按钮和菜单逻辑，只新增稳定分组外壳，不重写交互细节。

- [ ] **Step 6: 把 `WindowChromeConfiguration.app` 的 `titlePlacement` 改成 `.principal`**

在 `Sources/PowerShell/App/PowerShellApp.swift` 顶部把配置改成：

```swift
@MainActor
static let app = WindowChromeConfiguration(
    navigationTitle: nil,
    toolbarTitle: "PowerShell",
    titlePlacement: .principal
)
```

- [ ] **Step 7: 运行测试，确认协议与 toolbar 分组实现通过**

Run: `swift test --filter PowerShellAppTitleBarTests`

Expected: PASS，原有全屏 toolbar 测试继续通过，新增两个测试也通过。

- [ ] **Step 8: 提交 toolbar 协议与分组 view**

```bash
git add Sources/PowerShell/Plugins/PowerShellPlugin.swift \
        Sources/PowerShell/Plugins/PluginManager.swift \
        Sources/PowerShell/Plugins/SplitPlugin.swift \
        Sources/PowerShell/App/PowerShellApp.swift \
        Tests/PowerShellTests/PowerShellAppTitleBarTests.swift
git commit -m "feat: add split controls to trailing toolbar group"
```

---

## Task 3: 把分屏操作接入系统 toolbar，并移除 pane header 的旧承载

**Files:**
- Modify: `Sources/PowerShell/App/PowerShellApp.swift`
- Test: `Tests/PowerShellTests/PowerShellAppTitleBarTests.swift`
- Test: `Tests/PowerShellTests/SplitPluginToolbarPresentationTests.swift`

- [ ] **Step 1: 先让编译和测试作为“红灯”，确认旧 wiring 尚未接入 toolbar**

Run: `swift test --filter 'PowerShellAppTitleBarTests|SplitPluginToolbarPresentationTests'`

Expected: PASS；这一步的目的是在改动前确认基线稳定，然后再做最小 UI wiring 变更。

- [ ] **Step 2: 在 `RootContentView.body` 中读取 active session 的 toolbar trailing view**

在 `NavigationSplitView` 后、`.toolbar` 前先加一个局部变量所需的计算逻辑，最终让 `toolbar` 部分变成下面这样：

```swift
.toolbar {
    ToolbarItem(placement: chrome.titlePlacement) {
        Text(chrome.toolbarTitle)
            .fontWeight(.bold)
    }

    if let trailingToolbarView = PluginManager.shared.firstToolbarTrailingView(
        activeSession: sessionManager.sessions.first(where: { $0.id == sessionManager.activeSessionId }),
        allSessions: sessionManager.sessions
    ) {
        ToolbarItem(placement: .primaryAction) {
            trailingToolbarView
        }
    }
}
```

- [ ] **Step 3: 去掉 `terminalPane(for:geoWidth:geoHeight:)` 中旧的 header accessory 查找与传递**

把 `Sources/PowerShell/App/PowerShellApp.swift` 里的这两段删掉：

```swift
let accessory = PluginManager.shared.firstHeaderAccessory(for: session, allSessions: sessionManager.sessions)
```

```swift
headerAccessoryView: accessory
```

并让 `TerminalDetailView` 调用变成：

```swift
TerminalDetailView(
    session: session,
    themeManager: themeManager,
    isActive: isSingleActive || isPrimary,
    onSessionActivityChanged: { isActive in
        sessionManager.setActiveActivity(sessionId: session.id, isActive: isActive)
        if !isActive {
            PluginManager.shared.dispatchProcessTerminated(session: session)
        }
    },
    onDirectoryChanged: { directory in
        sessionManager.updateDirectory(sessionId: session.id, directory: directory)
        PluginManager.shared.dispatchDirectoryChanged(to: directory, session: session)
    },
    onAttentionNeeded: { type in
        guard session.id != sessionManager.activeSessionId else { return }
        switch type {
        case .oscNotification(let title, let msg):
            let body = "[\(session.name)] \(title): \(msg)"
            NotificationManager.shared.send(
                title: "PowerShell",
                body: body,
                sessionId: session.id.uuidString
            )
            sessionManager.incrementUnread(sessionId: session.id)
        }
    },
    onTerminalFocused: {
        sessionManager.clearUnread(sessionId: session.id)
        PluginManager.shared.dispatchTerminalFocused(session: session)
    }
)
```

- [ ] **Step 4: 从 `TerminalDetailView` 中移除 `headerAccessoryView` 属性和 header 里的 accessory 渲染**

把结构体定义里的这行删除：

```swift
var headerAccessoryView: AnyView? = nil
```

并把 header `HStack` 里的这段删除：

```swift
Spacer()

if let accessory = headerAccessoryView {
    accessory
}
```

改成只保留会话信息的稳定 header：

```swift
HStack(spacing: 8) {
    Circle()
        .fill(session.isActive ? Color.green : Color.gray.opacity(0.5))
        .frame(width: 8, height: 8)

    Text(headerPresentation.title)
        .font(.body)
        .lineLimit(1)

    Text(session.shellType.displayName)
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(.quaternary, in: Capsule())

    Spacer()
}
```

- [ ] **Step 5: 运行测试，确认迁移没有破坏状态逻辑与标题栏配置**

Run: `swift test --filter 'PowerShellAppTitleBarTests|SplitPluginToolbarPresentationTests'`

Expected: PASS。

- [ ] **Step 6: 运行完整测试集**

Run: `swift test`

Expected: PASS，全量 XCTest 通过。

- [ ] **Step 7: 本地启动 app 做手工验证**

Run: `swift run PowerShell`

按下面顺序手动验证：

1. 仅一个 session：toolbar 左侧是 sidebar 按钮，中间有 `PowerShell`，右侧没有分屏组
2. 创建第二个 session：右侧出现胶囊式分屏组，两个分屏按钮间距固定
3. 执行左右分屏：右侧出现 secondary 名称 + 取消分屏，整体仍是同一块胶囊区域
4. 再创建足够 session 后验证四宫格扩展入口出现，胶囊外观不跳
5. 调整窗口宽度、进入全屏再退出，确认标题与右侧分组不会出现异常重排

- [ ] **Step 8: 提交最终 UI 迁移**

```bash
git add Sources/PowerShell/App/PowerShellApp.swift \
        Sources/PowerShell/Plugins/SplitPlugin.swift
git commit -m "feat: stabilize split controls in system toolbar"
```

---

## 自检

### Spec coverage

- “保留系统 toolbar、保留中间 `PowerShell` 标题” → Task 2 Step 6 + Task 3 Step 2
- “右侧分屏操作区仅在有分屏 / 可操作时显示” → Task 1 Step 3 的 `SplitToolbarPresentation.hidden/splitActions/splitSummary/unsplitOnly`
- “内部间距、背景形态、图标尺寸保持稳定” → Task 2 Step 5 的 `SplitToolbarAccessoryView`
- “避免继续依赖 pane header accessory 承担顶部布局职责” → Task 3 Step 3-4
- “验证窗口宽度变化、全屏切换、四宫格流程” → Task 3 Step 7

### Placeholder scan

已检查本计划中没有 `TODO` / `TBD` / “自行实现” 之类占位描述；每个代码步骤都给了明确代码或命令。

### Type consistency

统一使用以下命名，没有在后续任务中改名：
- `SplitToolbarPresentation`
- `SplitToolbarPresentation.Target`
- `toolbarPresentation(activeSession:allSessions:)`
- `toolbarTrailingView(activeSession:allSessions:)`
- `firstToolbarTrailingView(activeSession:allSessions:)`
- `SplitToolbarAccessoryView`

---

Plan complete and saved to `docs/superpowers/plans/2026-05-01-toolbar-split-spacing.md`. Two execution options:

**1. Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints

**Which approach?**
