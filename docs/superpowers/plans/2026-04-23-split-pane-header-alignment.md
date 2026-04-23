# 分屏顶部栏样式统一 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让分屏左右两栏都显示同高度、同结构的顶部栏，并让右侧分栏也展示当前地址。

**Architecture:** 保持现有分屏布局、拖拽、分割线和 PTY 生命周期不变，只在 `Sources/PowerShell/App/PowerShellApp.swift` 内收敛 `TerminalDetailView` 的 header 渲染逻辑。先引入一个可测试的 `TerminalHeaderPresentation` 辅助类型，用纯单元测试锁定标题优先级和 trailing accessory 规则，再把视图改为始终渲染 header，并让 secondary pane 只展示信息、不重复展示分屏控制。

**Tech Stack:** Swift 6.0, SwiftUI (macOS 14+), XCTest, SPM

---

## 文件清单

| 文件 | 操作 | 职责 |
|------|------|------|
| `Sources/PowerShell/App/PowerShellApp.swift` | 修改 | 新增 `TerminalHeaderAccessory` / `TerminalHeaderPresentation`，并让 `TerminalDetailView` 始终渲染统一 header，按规则展示标题和 trailing accessory |
| `Tests/PowerShellTests/TerminalHeaderPresentationTests.swift` | 新建 | 覆盖 header 标题优先级、secondary pane 隐藏控制、primary pane 显示 split summary、单栏显示 split menu |

---

## Task 1: 用测试锁定 header 展示规则

**Files:**
- Create: `Tests/PowerShellTests/TerminalHeaderPresentationTests.swift`
- Modify: `Sources/PowerShell/App/PowerShellApp.swift`

- [ ] **Step 1: 新建测试文件，写失败测试覆盖标题优先级和 accessory 规则**

```swift
// Tests/PowerShellTests/TerminalHeaderPresentationTests.swift
import XCTest
@testable import PowerShell

@MainActor
final class TerminalHeaderPresentationTests: XCTestCase {
    func testHeaderTitlePrefersCurrentDirectory() {
        var session = Session(name: "终端 1", shellType: .zsh, isActive: true)
        session.currentDirectory = "/Users/bytedance/work"

        let presentation = TerminalHeaderPresentation(
            session: session,
            terminalTitle: "bytedance@host:~",
            splitSecondaryName: nil,
            isSplitSecondary: false
        )

        XCTAssertEqual(presentation.title, "/Users/bytedance/work")
        XCTAssertEqual(presentation.accessory, .splitMenu)
    }

    func testHeaderTitleFallsBackToTerminalTitleThenSessionName() {
        let session = Session(name: "终端 2", shellType: .bash, isActive: false)

        let withTerminalTitle = TerminalHeaderPresentation(
            session: session,
            terminalTitle: "bytedance@host:/tmp",
            splitSecondaryName: nil,
            isSplitSecondary: false
        )
        XCTAssertEqual(withTerminalTitle.title, "bytedance@host:/tmp")

        let withSessionName = TerminalHeaderPresentation(
            session: session,
            terminalTitle: "",
            splitSecondaryName: nil,
            isSplitSecondary: false
        )
        XCTAssertEqual(withSessionName.title, "终端 2")
    }

    func testHeaderAccessoryHidesControlsForSecondaryPane() {
        let session = Session(name: "终端 3", shellType: .zsh, isActive: false)

        let presentation = TerminalHeaderPresentation(
            session: session,
            terminalTitle: "",
            splitSecondaryName: nil,
            isSplitSecondary: true
        )

        XCTAssertEqual(presentation.accessory, .none)
    }

    func testHeaderAccessoryShowsSplitSummaryForPrimaryPane() {
        let session = Session(name: "终端 1", shellType: .zsh, isActive: true)

        let presentation = TerminalHeaderPresentation(
            session: session,
            terminalTitle: "",
            splitSecondaryName: "终端 2",
            isSplitSecondary: false
        )

        XCTAssertEqual(presentation.accessory, .splitSummary("终端 2"))
    }
}
```

- [ ] **Step 2: 运行测试，确认失败**

Run: `swift test --filter TerminalHeaderPresentationTests 2>&1 | tail -20`

Expected: FAIL，提示 `cannot find 'TerminalHeaderPresentation' in scope` 或 `cannot infer contextual base in reference to member 'splitMenu'`。

- [ ] **Step 3: 在 `Sources/PowerShell/App/PowerShellApp.swift` 的 `// MARK: - Terminal Detail View` 前新增可测试 helper 类型**

```swift
enum TerminalHeaderAccessory: Equatable {
    case splitMenu
    case splitSummary(String)
    case none
}

struct TerminalHeaderPresentation: Equatable {
    let title: String
    let accessory: TerminalHeaderAccessory

    init(
        session: Session,
        terminalTitle: String,
        splitSecondaryName: String?,
        isSplitSecondary: Bool
    ) {
        if let currentDirectory = session.currentDirectory, !currentDirectory.isEmpty {
            title = currentDirectory
        } else if !terminalTitle.isEmpty {
            title = terminalTitle
        } else {
            title = session.name
        }

        if isSplitSecondary {
            accessory = .none
        } else if let splitSecondaryName {
            accessory = .splitSummary(splitSecondaryName)
        } else {
            accessory = .splitMenu
        }
    }
}
```

- [ ] **Step 4: 运行测试，确认通过**

Run: `swift test --filter TerminalHeaderPresentationTests 2>&1 | tail -20`

Expected: PASS，4 个 `TerminalHeaderPresentationTests` 全部通过。

- [ ] **Step 5: 提交 helper 和测试**

```bash
git add Sources/PowerShell/App/PowerShellApp.swift \
        Tests/PowerShellTests/TerminalHeaderPresentationTests.swift
git commit -m "test: lock split pane header presentation rules"
```

---

## Task 2: 让左右两栏始终渲染统一 header

**Files:**
- Modify: `Sources/PowerShell/App/PowerShellApp.swift`
- Test: `Tests/PowerShellTests/TerminalHeaderPresentationTests.swift`

- [ ] **Step 1: 在 `TerminalDetailView` 中新增 headerPresentation 计算属性和 headerAccessory 视图**

把下面代码加到 `TerminalDetailView` 内、`var body: some View` 之前：

```swift
private var headerPresentation: TerminalHeaderPresentation {
    TerminalHeaderPresentation(
        session: session,
        terminalTitle: terminalTitle,
        splitSecondaryName: splitSecondaryName,
        isSplitSecondary: isSplitSecondary
    )
}

@ViewBuilder
private var headerAccessory: some View {
    switch headerPresentation.accessory {
    case .splitSummary(let secName):
        Text("│")
            .foregroundStyle(.tertiary)
        Text(secName)
            .font(.caption)
            .foregroundStyle(.secondary)
        Button {
            onUnsplit?()
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help("取消分屏")

    case .splitMenu:
        Menu {
            ForEach(availableSessionsForSplit, id: \.id) { s in
                Button(s.name) {
                    onSplitRequested?(session.id, s.id)
                }
            }
        } label: {
            Image(systemName: "rectangle.split.1x2")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .help("分屏显示另一个终端")

    case .none:
        EmptyView()
    }
}
```

- [ ] **Step 2: 替换 `TerminalDetailView.body` 里现有 header 区块，去掉 `if !isSplitSecondary` 分支**

把现有这段：

```swift
VStack(spacing: 0) {
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

            Spacer()

            if let secName = splitSecondaryName {
                Text("│")
                    .foregroundStyle(.tertiary)
                Text(secName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button {
                    onUnsplit?()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("取消分屏")
            } else {
                Menu {
                    ForEach(availableSessionsForSplit, id: \.id) { s in
                        Button(s.name) {
                            onSplitRequested?(session.id, s.id)
                        }
                    }
                } label: {
                    Image(systemName: "rectangle.split.1x2")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .help("分屏显示另一个终端")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)

        Divider()
    }

    TerminalPaneView(
```

替换为：

```swift
VStack(spacing: 0) {
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

        headerAccessory
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 6)
    .background(.bar)

    Divider()

    TerminalPaneView(
```

- [ ] **Step 3: 运行定向测试和构建，确认 helper 与视图接线都通过**

Run: `swift test --filter TerminalHeaderPresentationTests 2>&1 | tail -20 && swift build 2>&1 | tail -20`

Expected: `TerminalHeaderPresentationTests` 通过，随后 `Build complete!`。

- [ ] **Step 4: 提交统一 header 渲染改动**

```bash
git add Sources/PowerShell/App/PowerShellApp.swift
git commit -m "feat: align split pane headers"
```

---

## Task 3: 手动验证分屏 UI 与回归

**Files:**
- Modify: none
- Verify: `Sources/PowerShell/App/PowerShellApp.swift`

- [ ] **Step 1: 启动应用进行手动检查**

Run: `swift run PowerShell`

Expected: 应用启动成功并出现主窗口。

- [ ] **Step 2: 按下面清单手动验证分屏顶部栏**

```text
1. 新建两个终端并进入分屏模式。
2. 确认左右两栏顶部栏高度一致。
3. 确认左右两栏顶部栏背景、Divider、padding、状态点、shell 标签样式一致。
4. 在右侧终端执行 `pwd` 后切换目录，确认右侧顶部文本展示当前地址。
5. 确认左侧 primary pane 仍可取消分屏，右侧 secondary pane 不出现重复的分屏按钮或取消按钮。
6. 拖动分割线，确认顶部栏仍保持对齐，没有错位或高度变化。
7. 退出分屏后确认单栏 header 仍正常显示 split menu。
```

Expected: 7 项全部满足，没有新的布局回归。

- [ ] **Step 3: 运行全量测试，确认没有回归**

Run: `swift test 2>&1 | tail -20`

Expected: 所有测试通过，无新增失败。

- [ ] **Step 4: 提交最终验证通过的代码**

```bash
git add Sources/PowerShell/App/PowerShellApp.swift \
        Tests/PowerShellTests/TerminalHeaderPresentationTests.swift
git commit -m "test: verify split pane header alignment"
```

---

## Self-Review

### Spec coverage

- “左右分栏顶部区域高度一致” → Task 2 Step 2 让 secondary pane 也始终渲染同一套 header。
- “左右分栏顶部区域视觉结构一致” → Task 2 Step 2 保留统一的状态点、标题、shell 标签、背景和 Divider 结构。
- “右侧分栏也展示当前地址” → Task 1 Step 3 的 `TerminalHeaderPresentation` 把 `session.currentDirectory` 设为最高优先级。
- “primary 保留控制、secondary 不重复控制” → Task 1 Step 3 的 `.none` / `.splitSummary` / `.splitMenu` accessory 规则。
- “不改动分屏布局、拖拽、PTY 生命周期” → 文件清单只修改 `PowerShellApp.swift` 与新测试文件，没有触碰 `SessionManager`、`SplitDividerView`、`SidebarView` 或 `TerminalPaneView` 生命周期代码。

### Placeholder scan

- 无 `TODO` / `TBD` / “implement later”。
- 所有代码步骤都提供了具体代码块。
- 所有验证步骤都提供了精确命令和期望结果。

### Type consistency

- 计划中统一使用 `TerminalHeaderAccessory`、`TerminalHeaderPresentation`、`headerPresentation`、`headerAccessory` 四个名字。
- `TerminalHeaderPresentation` 初始化参数始终是 `session`、`terminalTitle`、`splitSecondaryName`、`isSplitSecondary`，前后保持一致。

---
