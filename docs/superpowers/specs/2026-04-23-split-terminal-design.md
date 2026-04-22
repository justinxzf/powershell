# 并排多终端（分屏）设计文档

**日期**: 2026-04-23  
**状态**: 已确认，待实施

---

## 概述

在 PowerShell 终端 App 中新增"分屏"功能，允许用户通过拖拽操作将两个终端会话并排展示，并通过拖动分割线调整比例。

---

## 需求

- 最多 **2 个**终端并排（主 + 1 辅）
- 触发：从 sidebar 拖拽「终端2」放到「终端1」的标题栏 → 分屏
- 取消：从组合标题栏拖拽「终端2」token 回 sidebar → 取消分屏
- 默认比例 **50/50**，可通过拖动分割线调整（限制 20%~80%）
- PTY 进程在模式切换时**不重建**

---

## 第一节：数据模型（SessionManager）

### 新增字段

```swift
var splitPair: (primary: UUID, secondary: UUID)?  // nil = 单栏模式
var splitRatio: Double = 0.5                      // 分割线位置，范围 0~1
```

### 新增方法

```swift
func split(primary: UUID, secondary: UUID) {
    splitPair = (primary, secondary)
    splitRatio = 0.5
}

func unsplit() {
    splitPair = nil
}
```

### 修改 `delete(sessionId:)`

```swift
// 在现有逻辑之前加入：
if let pair = splitPair, pair.primary == sessionId || pair.secondary == sessionId {
    unsplit()
}
```

**不改动**：`activeSessionId`、`claudeSessionMap`、`powershellSessionIndex`、通知路由——全部保持原样。

---

## 第二节：主内容区布局（RootContentView）

### 核心原则

所有 session 的 `TerminalDetailView` 始终保留在 ZStack 内（保证 PTY 进程不被释放）。分屏时仅修改每个 view 的 `.frame(width:)` 和 `.offset(x:)`，不改变 view 层级，SwiftUI 不会触发 `makeNSView`。

### 布局计算

```swift
// 在 RootContentView detail 区域：
GeometryReader { geo in
    ZStack(alignment: .topLeading) {
        ForEach(sessionManager.sessions) { session in
            TerminalDetailView(
                session: session,
                isSplitPrimary: sessionManager.splitPair?.primary == session.id,
                splitSecondaryName: splitSecondaryName(for: session),
                isActive: isActive(session),
                ...
            )
            .frame(width: paneWidth(session, geo.size.width), height: geo.size.height)
            .offset(x: paneOffsetX(session, geo.size.width))
            .opacity(paneOpacity(session))
            .allowsHitTesting(paneInteractive(session))
        }

        // 分割线 overlay（仅分屏时显示）
        if sessionManager.splitPair != nil {
            SplitDividerView(ratio: $sessionManager.splitRatio, totalWidth: geo.size.width)
        }
    }
}
```

### 计算函数逻辑

| 场景 | paneWidth | paneOffsetX | opacity | hitTesting |
|------|-----------|-------------|---------|------------|
| 单栏，active session | fullWidth | 0 | 1 | true |
| 单栏，其他 session | fullWidth | 0 | 0 | false |
| 分屏，primary | fullWidth × ratio | 0 | 1 | true |
| 分屏，secondary | fullWidth × (1−ratio) | fullWidth × ratio | 1 | true |
| 分屏，其他 session | fullWidth | 0 | 0 | false |

### Sidebar 显示

分屏时 sidebar 保持两个独立条目，active session 高亮为 primary session ID。

---

## 第三节：标题栏（TerminalDetailView）

### 新增参数

```swift
struct TerminalDetailView: View {
    // 现有参数不变，新增：
    var isSplitPrimary: Bool = false         // 分屏主 pane
    var isSplitSecondary: Bool = false       // 分屏副 pane（隐藏标题栏）
    var splitSecondaryName: String? = nil    // 非 nil 时显示组合标题
    var splitSecondaryId: UUID? = nil        // 用于 secondary token 的 .draggable payload
    var onUnsplit: (() -> Void)? = nil
    ...
}
```

### 标题栏渲染逻辑

- **单栏 / 分屏主 pane（`isSplitPrimary = true`）**：显示完整标题栏
  - 若 `splitSecondaryName != nil`：标题右侧追加可拖拽 token「`○ 终端2 ↔`」
  - token 添加 `.draggable(splitSecondaryId!.uuidString)`
- **分屏副 pane（`isSplitSecondary = true`）**：隐藏标题栏（节省垂直空间，避免重复）
- **单栏普通 pane**：显示完整标题栏（现有行为不变）

### 拖拽高亮

当外部 session 被拖拽悬停在标题栏上方时，标题栏背景切换为 accent 色，提示可放置。

---

## 第四节：拖拽交互

### 触发分屏

```swift
// SidebarItemRow：session id 作为 payload
SidebarItemRow(...)
    .draggable(session.id.uuidString)

// TerminalDetailView 标题栏区域
titleBarArea
    .dropDestination(for: String.self) { items, _ in
        guard let droppedId = UUID(uuidString: items.first ?? ""),
              droppedId != session.id,
              sessionManager.splitPair == nil   // 已分屏不响应
        else { return false }
        sessionManager.split(primary: session.id, secondary: droppedId)
        return true
    } isTargeted: { isTargeted in
        titleBarHighlighted = isTargeted
    }
```

### 取消分屏

```swift
// 组合标题栏中的 secondary token
secondaryToken
    .draggable(secondarySession.id.uuidString)

// SidebarView list 接收 drop
sidebarList
    .dropDestination(for: String.self) { items, _ in
        guard let droppedId = UUID(uuidString: items.first ?? ""),
              sessionManager.splitPair?.secondary == droppedId
        else { return false }
        sessionManager.unsplit()
        return true
    }
```

### 边界处理

| 情况 | 处理方式 |
|------|----------|
| 拖拽到 sidebar 以外区域 | macOS spring-back 动画，split 保持不变 |
| 删除分屏中的任一 session | `delete()` 内自动调用 `unsplit()` |
| 已分屏时再次拖入标题栏 | drop target 返回 `false`，无响应 |
| 拖入 session 与当前 session 相同 | drop target 返回 `false`，无响应 |

---

## 第五节：SplitDividerView

```swift
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
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        isDragging = true
                        let newRatio = (totalWidth * ratio + value.translation.width) / totalWidth
                        ratio = max(0.2, min(0.8, newRatio))
                    }
                    .onEnded { _ in isDragging = false }
            )
            .contentShape(Rectangle().inset(by: -8))  // 扩大 16pt 热区
            .onHover { hovering in
                if hovering { NSCursor.resizeLeftRight.push() }
                else { NSCursor.pop() }
            }
    }
}
```

**要点**：ratio 限制 20%~80%，防止某侧消失；拖动时分割线高亮为 accent 色。

---

## 变更文件清单

| 文件 | 变更类型 | 说明 |
|------|----------|------|
| `ViewModels/SessionManager.swift` | 修改 | 新增 splitPair、splitRatio、split()、unsplit()；修改 delete() |
| `App/PowerShellApp.swift` | 修改 | RootContentView detail 区域改用 GeometryReader + 动态 frame/offset |
| `Views/TerminalView.swift` | 修改 | TerminalDetailView 新增 isSplitPrimary、splitSecondaryName、onUnsplit 参数；标题栏渲染分支 |
| `Views/SidebarView.swift` | 修改 | SidebarItemRow 添加 .draggable；SidebarView list 添加 .dropDestination |
| `Views/SplitDividerView.swift` | 新建 | 独立文件，可拖动分割线组件 |
