# 并排多终端（分屏）实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 通过拖拽交互让用户将两个终端并排显示，拖走取消分屏，不重建任何 PTY 进程。

**Architecture:** 在 `SessionManager` 新增 `splitPair` 和 `splitRatio` 两个字段；`RootContentView` 用 `GeometryReader` 包裹 ZStack，所有 TerminalDetailView 始终保留，通过动态 `frame/offset/opacity` 实现分屏布局；新建 `SplitDividerView` 作为可拖动分割线；拖拽 payload 为 UUID string，符合 SwiftUI Transferable 机制。

**Tech Stack:** Swift 6.0, SwiftUI (macOS 14+), SwiftTerm 1.13.0, SPM

---

## 文件清单

| 文件 | 操作 | 职责 |
|------|------|------|
| `Sources/PowerShell/ViewModels/SessionManager.swift` | 修改 | 新增 splitPair、splitRatio、split()、unsplit()；修改 delete() |
| `Sources/PowerShell/Views/SplitDividerView.swift` | 新建 | 可拖动分割线组件 |
| `Sources/PowerShell/App/PowerShellApp.swift` | 修改 | RootContentView detail 区域改为 GeometryReader + 动态布局计算 |
| `Sources/PowerShell/Views/TerminalView.swift` | 修改 | TerminalDetailView 新增 isSplitPrimary/isSplitSecondary 等参数，标题栏渲染分支 |
| `Sources/PowerShell/Views/SidebarView.swift` | 修改 | SidebarItemRow 添加 .draggable；SidebarView list 添加 .dropDestination 取消分屏 |
| `Tests/PowerShellTests/SessionManagerSplitTests.swift` | 新建 | SessionManager 分屏逻辑单元测试 |

---

## Task 1: SessionManager — 新增分屏状态与方法

**Files:**
- Modify: `Sources/PowerShell/ViewModels/SessionManager.swift`
- Create: `Tests/PowerShellTests/SessionManagerSplitTests.swift`

- [ ] **Step 1: 新建测试文件，写第一个失败测试（split 建立分屏）**

```swift
// Tests/PowerShellTests/SessionManagerSplitTests.swift
import XCTest
@testable import PowerShell

@MainActor
final class SessionManagerSplitTests: XCTestCase {

    func test_split_setsSplitPair() {
        let manager = SessionManager()
        let s1 = manager.createSession(name: "A")
        let s2 = manager.createSession(name: "B")

        manager.split(primary: s1.id, secondary: s2.id)

        XCTAssertEqual(manager.splitPair?.primary, s1.id)
        XCTAssertEqual(manager.splitPair?.secondary, s2.id)
        XCTAssertEqual(manager.splitRatio, 0.5)
    }
}
```

- [ ] **Step 2: 运行测试，确认失败**

```bash
swift test --filter SessionManagerSplitTests/test_split_setsSplitPair 2>&1 | tail -20
```

期望：`error: cannot find 'split' in scope` 或编译错误。

- [ ] **Step 3: 在 SessionManager.swift 新增字段和方法**

在 `SessionManager` class 的 `var activeSessionId` 后面加：

```swift
var splitPair: (primary: UUID, secondary: UUID)?
var splitRatio: Double = 0.5
```

在 `delete(sessionId:)` 方法**之前**加：

```swift
func split(primary: UUID, secondary: UUID) {
    splitPair = (primary: primary, secondary: secondary)
    splitRatio = 0.5
}

func unsplit() {
    splitPair = nil
}
```

- [ ] **Step 4: 运行测试，确认通过**

```bash
swift test --filter SessionManagerSplitTests/test_split_setsSplitPair 2>&1 | tail -10
```

期望：`Test Suite 'SessionManagerSplitTests' passed`

- [ ] **Step 5: 补充 unsplit 和 delete 边界测试**

追加到 `SessionManagerSplitTests.swift`：

```swift
func test_unsplit_clearsSplitPair() {
    let manager = SessionManager()
    let s1 = manager.createSession(name: "A")
    let s2 = manager.createSession(name: "B")
    manager.split(primary: s1.id, secondary: s2.id)

    manager.unsplit()

    XCTAssertNil(manager.splitPair)
}

func test_delete_primary_callsUnsplit() {
    let manager = SessionManager()
    let s1 = manager.createSession(name: "A")
    let s2 = manager.createSession(name: "B")
    manager.split(primary: s1.id, secondary: s2.id)

    manager.delete(sessionId: s1.id)

    XCTAssertNil(manager.splitPair)
}

func test_delete_secondary_callsUnsplit() {
    let manager = SessionManager()
    let s1 = manager.createSession(name: "A")
    let s2 = manager.createSession(name: "B")
    manager.split(primary: s1.id, secondary: s2.id)

    manager.delete(sessionId: s2.id)

    XCTAssertNil(manager.splitPair)
}

func test_delete_unrelated_doesNotUnsplit() {
    let manager = SessionManager()
    let s1 = manager.createSession(name: "A")
    let s2 = manager.createSession(name: "B")
    let s3 = manager.createSession(name: "C")
    manager.split(primary: s1.id, secondary: s2.id)

    manager.delete(sessionId: s3.id)

    XCTAssertNotNil(manager.splitPair)
}
```

- [ ] **Step 6: 运行新测试，确认失败（delete 尚未修改）**

```bash
swift test --filter SessionManagerSplitTests 2>&1 | tail -20
```

期望：`test_delete_primary_callsUnsplit` 和 `test_delete_secondary_callsUnsplit` 失败。

- [ ] **Step 7: 修改 `delete(sessionId:)` 在 SessionManager.swift**

在 `delete(sessionId:)` 方法的**第一行**插入：

```swift
func delete(sessionId: UUID) {
    // 新增：若被删 session 在分屏中，先取消分屏
    if let pair = splitPair, pair.primary == sessionId || pair.secondary == sessionId {
        unsplit()
    }
    // 以下保持原有逻辑不变
    sessions.removeAll { $0.id == sessionId }
    ...
}
```

- [ ] **Step 8: 运行全部分屏测试，确认全部通过**

```bash
swift test --filter SessionManagerSplitTests 2>&1 | tail -15
```

期望：4 个测试全部 `passed`。

- [ ] **Step 9: 运行全部测试，确认没有回归**

```bash
swift test 2>&1 | tail -20
```

期望：所有测试通过，无新失败。

- [ ] **Step 10: 提交**

```bash
git add Sources/PowerShell/ViewModels/SessionManager.swift \
        Tests/PowerShellTests/SessionManagerSplitTests.swift
git commit -m "feat: add splitPair/splitRatio state and split/unsplit methods to SessionManager"
```

---

## Task 2: 新建 SplitDividerView

**Files:**
- Create: `Sources/PowerShell/Views/SplitDividerView.swift`

- [ ] **Step 1: 创建文件**

```swift
// Sources/PowerShell/Views/SplitDividerView.swift
import SwiftUI
import AppKit

struct SplitDividerView: View {
    @Binding var ratio: Double
    let totalWidth: CGFloat

    @State private var isDragging = false

    var body: some View {
        Rectangle()
            .fill(isDragging ? Color.accentColor : Color(nsColor: .separatorColor))
            .frame(width: isDragging ? 3 : 1)
            .frame(maxHeight: .infinity)
            .offset(x: totalWidth * ratio - 1)
            .contentShape(Rectangle().inset(by: -8))
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        isDragging = true
                        let newRatio = (totalWidth * ratio + value.translation.width) / totalWidth
                        ratio = max(0.2, min(0.8, newRatio))
                    }
                    .onEnded { _ in isDragging = false }
            )
            .onHover { hovering in
                if hovering { NSCursor.resizeLeftRight.push() }
                else { NSCursor.pop() }
            }
    }
}
```

- [ ] **Step 2: 确认编译通过**

```bash
swift build 2>&1 | tail -10
```

期望：`Build complete!`

- [ ] **Step 3: 提交**

```bash
git add Sources/PowerShell/Views/SplitDividerView.swift
git commit -m "feat: add SplitDividerView — draggable split line with resize cursor"
```

---

## Task 3: TerminalDetailView — 新增分屏参数与标题栏渲染

**Files:**
- Modify: `Sources/PowerShell/Views/TerminalView.swift`（`TerminalDetailView` struct，约 297-384 行）

- [ ] **Step 1: 在 TerminalDetailView 定义中新增参数**

找到 `struct TerminalDetailView: View {` 的属性声明区，在 `var onTerminalFocused: (() -> Void)?` **之后**加入：

```swift
var isSplitPrimary: Bool = false
var isSplitSecondary: Bool = false
var splitSecondaryName: String? = nil
var splitSecondaryId: UUID? = nil
var onUnsplit: (() -> Void)? = nil
```

- [ ] **Step 2: 修改标题栏 HStack 渲染逻辑**

找到 `TerminalDetailView.body` 内的 `VStack(spacing: 0)` 里的标题栏区域（当前是一个 `HStack` + `.background(.bar)`），替换为：

```swift
// 分屏副 pane 不显示标题栏
if !isSplitSecondary {
    HStack(spacing: 8) {
        Circle()
            .fill(session.isActive ? Color.green : Color.gray.opacity(0.5))
            .frame(width: 8, height: 8)

        Text(terminalTitle.isEmpty ? session.name : terminalTitle)
            .font(.body)
            .lineLimit(1)

        Text(session.shellType.displayName)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.quaternary, in: Capsule())

        // 分屏主 pane：显示 secondary token，可拖回 sidebar 取消分屏
        if let secName = splitSecondaryName, let secId = splitSecondaryId {
            Text("│")
                .foregroundStyle(.tertiary)
                .font(.body)
            Text("○ \(secName) ↔")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary, in: Capsule())
                .draggable(secId.uuidString)
                .help("拖回侧边栏取消分屏")
        }

        Spacer()
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 6)
    .background(.bar)

    Divider()
}
```

- [ ] **Step 3: 确认编译通过**

```bash
swift build 2>&1 | tail -10
```

期望：`Build complete!`

- [ ] **Step 4: 提交**

```bash
git add Sources/PowerShell/Views/TerminalView.swift
git commit -m "feat: TerminalDetailView supports split primary/secondary title bar rendering"
```

---

## Task 4: RootContentView — GeometryReader + 动态布局

**Files:**
- Modify: `Sources/PowerShell/App/PowerShellApp.swift`（`RootContentView` 的 `detail` 区域，约 98-153 行）

- [ ] **Step 1: 将 detail 区域替换为 GeometryReader + 动态计算**

找到 `RootContentView.body` 中 `NavigationSplitView` 的 `detail:` 闭包，将整个 `ZStack { ... }` 替换为：

```swift
detail: {
    GeometryReader { geo in
        ZStack(alignment: .topLeading) {
            ForEach(sessionManager.sessions) { session in
                let isPrimary = sessionManager.splitPair?.primary == session.id
                let isSecondary = sessionManager.splitPair?.secondary == session.id
                let isInSplit = isPrimary || isSecondary
                let isSingleActive = sessionManager.splitPair == nil && session.id == sessionManager.activeSessionId

                // 计算 pane 宽度
                let paneW: CGFloat = {
                    if isPrimary { return geo.size.width * sessionManager.splitRatio }
                    if isSecondary { return geo.size.width * (1 - sessionManager.splitRatio) }
                    return geo.size.width
                }()

                // 计算 pane 水平偏移
                let paneX: CGFloat = isSecondary ? geo.size.width * sessionManager.splitRatio : 0

                // secondary session 的名称（用于 primary 标题栏显示）
                let secName: String? = isPrimary
                    ? sessionManager.sessions.first(where: { $0.id == sessionManager.splitPair?.secondary })?.name
                    : nil
                let secId: UUID? = isPrimary ? sessionManager.splitPair?.secondary : nil

                TerminalDetailView(
                    session: session,
                    themeManager: themeManager,
                    isActive: isSingleActive || isPrimary,
                    isSplitPrimary: isPrimary,
                    isSplitSecondary: isSecondary,
                    splitSecondaryName: secName,
                    splitSecondaryId: secId,
                    onUnsplit: { sessionManager.unsplit() },
                    onSessionActivityChanged: { isActive in
                        sessionManager.setActiveActivity(sessionId: session.id, isActive: isActive)
                    },
                    onDirectoryChanged: { directory in
                        sessionManager.updateDirectory(sessionId: session.id, directory: directory)
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
                    }
                )
                .frame(width: paneW, height: geo.size.height)
                .offset(x: paneX)
                .opacity(isSingleActive || isInSplit ? 1 : 0)
                .allowsHitTesting(isSingleActive || isInSplit)
            }

            // 分割线（仅分屏时显示）
            if sessionManager.splitPair != nil {
                SplitDividerView(
                    ratio: $sessionManager.splitRatio,
                    totalWidth: geo.size.width
                )
            }

            // 无 session 时的空态
            if sessionManager.sessions.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "terminal")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("No Active Session")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Button("Create Session") {
                        _ = sessionManager.createSession()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}
```

> **注意**：上面代码中的空态判断移到了 ZStack 内部（原来的 `if sessionManager.activeSession == nil` 改为 `if sessionManager.sessions.isEmpty`）。

- [ ] **Step 2: 确认编译通过**

```bash
swift build 2>&1 | tail -15
```

期望：`Build complete!`（如有参数名不匹配的编译错误，按错误提示修正参数顺序）

- [ ] **Step 3: 运行全部测试，确认无回归**

```bash
swift test 2>&1 | tail -15
```

期望：所有测试通过。

- [ ] **Step 4: 提交**

```bash
git add Sources/PowerShell/App/PowerShellApp.swift
git commit -m "feat: RootContentView uses GeometryReader for dynamic split pane layout"
```

---

## Task 5: SidebarView — 拖拽触发分屏 + 接收取消

**Files:**
- Modify: `Sources/PowerShell/Views/SidebarView.swift`

- [ ] **Step 1: SidebarItemRow 添加 .draggable**

找到 `SidebarItemRow` struct 的 `body` 里最外层的 `HStack(...).padding(...)` 末尾，加入：

```swift
.draggable(session.id.uuidString)
```

完整 body 末尾：
```swift
    .padding(.vertical, 2)
    .onChange(of: session.needsRename) { ... }
    .draggable(session.id.uuidString)   // ← 新增
```

- [ ] **Step 2: SidebarView 的 List 添加 .dropDestination（接收取消分屏）**

找到 `SidebarView.body` 里的 `List(selection:) { ... }` 末尾，在 `.listStyle(.sidebar)` 之后加：

```swift
.dropDestination(for: String.self) { items, _ in
    guard let droppedIdString = items.first,
          let droppedId = UUID(uuidString: droppedIdString),
          sessionManager.splitPair?.secondary == droppedId
    else { return false }
    sessionManager.unsplit()
    return true
}
```

- [ ] **Step 3: TerminalDetailView 标题栏添加 .dropDestination（接收触发分屏）**

打开 `Sources/PowerShell/Views/TerminalView.swift`，在 `TerminalDetailView.body` 标题栏 HStack 外层加上 drop 目标和高亮状态。

在 `TerminalDetailView` struct 里加一个 `@State`：

```swift
@State private var titleBarDropTargeted = false
```

然后将标题栏 `HStack` 的 `.background(.bar)` 改为：

```swift
.background(titleBarDropTargeted ? Color.accentColor.opacity(0.25) : Color(nsColor: .windowBackgroundColor))
```

并在 `HStack` 后（`Divider()` 之前）加：

```swift
.dropDestination(for: String.self) { items, _ in
    guard !isSplitSecondary,
          let droppedIdString = items.first,
          let droppedId = UUID(uuidString: droppedIdString),
          droppedId != session.id
    else { return false }
    // 通过回调通知外层触发 split（外层持有 sessionManager）
    onSplitRequested?(session.id, droppedId)
    return true
} isTargeted: { targeted in
    if !isSplitSecondary { titleBarDropTargeted = targeted }
}
```

同时在 `TerminalDetailView` 属性声明区新增回调：

```swift
var onSplitRequested: ((UUID, UUID) -> Void)? = nil
```

- [ ] **Step 4: 在 RootContentView 传入 onSplitRequested**

打开 `Sources/PowerShell/App/PowerShellApp.swift`，在 Task 4 生成的 `TerminalDetailView(...)` 调用中补充参数（加在 `onUnsplit:` 后面）：

```swift
onSplitRequested: { primaryId, secondaryId in
    guard sessionManager.splitPair == nil else { return }
    sessionManager.split(primary: primaryId, secondary: secondaryId)
},
```

- [ ] **Step 5: 确认编译通过**

```bash
swift build 2>&1 | tail -10
```

期望：`Build complete!`

- [ ] **Step 6: 运行全部测试，确认无回归**

```bash
swift test 2>&1 | tail -15
```

期望：所有测试通过。

- [ ] **Step 7: 提交**

```bash
git add Sources/PowerShell/Views/SidebarView.swift \
        Sources/PowerShell/Views/TerminalView.swift \
        Sources/PowerShell/App/PowerShellApp.swift
git commit -m "feat: drag-to-split and drag-back-to-unsplit interaction"
```

---

## Task 6: 手动验收测试

- [ ] **Step 1: 构建并运行 App**

```bash
swift run PowerShell
```

- [ ] **Step 2: 验收清单**

| 场景 | 操作 | 期望结果 |
|------|------|----------|
| 创建两个终端 | 点击「+」两次，创建「终端1」「终端2」 | sidebar 显示两个条目 |
| 触发分屏 | 拖拽 sidebar 中「终端2」到「终端1」的标题栏 | 两个终端并排 50/50，标题栏显示「终端1 │ ○ 终端2 ↔」 |
| 标题栏高亮 | 拖拽过程中悬停在标题栏上 | 标题栏出现蓝色高亮背景 |
| 调整比例 | 拖拽分割线左右移动 | 比例实时更新，不超出 20%~80% 范围 |
| 悬停分割线 | 鼠标移到分割线上 | 光标变为左右调整箭头 |
| PTY 不重建 | 分屏/取消分屏前后，两侧终端历史记录保持不变 | 历史记录未丢失 |
| 取消分屏 | 从标题栏拖拽「○ 终端2 ↔」回 sidebar | 恢复单栏，分割线消失 |
| 删除分屏中的 session | 右键「终端1」→ 关闭 | 自动取消分屏，退回单栏 |
| 已分屏再次拖入 | 再拖一个 session 到标题栏 | 无响应，分屏不变 |

- [ ] **Step 3: 发现问题则修复，修复后重新运行测试**

```bash
swift test 2>&1 | tail -15
```

- [ ] **Step 4: 最终提交（如有修复）**

```bash
git add -p
git commit -m "fix: address issues found during manual split-terminal acceptance testing"
```
