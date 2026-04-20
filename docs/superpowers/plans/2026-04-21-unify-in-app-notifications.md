# In-App Notification Unification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every PowerShell notification use the existing top-right in-app floating panel in both debug and DMG/app-bundle launches.

**Architecture:** Collapse `NotificationManager` from a dual-path notification coordinator into a single-path floating notification router. Keep the existing panel presenter and session-opening callback behavior, remove startup authorization requests, and update tests/documentation so they describe one notification path instead of app-bundle fallback behavior.

**Tech Stack:** Swift 6, SwiftUI, AppKit, XCTest

---

## File Structure

- Modify: `Sources/PowerShell/Services/NotificationManager.swift` — remove all `UNUserNotificationCenter`-specific types, state, and delegate behavior; keep only floating presenter routing and session-open callback bridging.
- Modify: `Sources/PowerShell/App/PowerShellApp.swift:188-191` — remove the startup authorization request so app launch no longer depends on system notification permissions.
- Modify: `Tests/PowerShellTests/NotificationManagerFloatingFallbackTests.swift` — replace fallback/bundle-specific tests with single-path floating notification routing tests while preserving panel interaction coverage.
- Modify: `feature/trd/notification.md:173-272` — update the documented notification architecture from dual-channel fallback to unified in-app floating notifications.

## Task 1: Rewrite notification tests to express single-path floating behavior

**Files:**
- Modify: `Tests/PowerShellTests/NotificationManagerFloatingFallbackTests.swift`
- Modify later: `Sources/PowerShell/Services/NotificationManager.swift`

- [ ] **Step 1: Write the failing test for unconditional floating routing**

Replace the top routing test with this exact test code:

```swift
func testSendAlwaysUsesFloatingPresenter() {
    let presenter = RecordingFloatingNotificationPresenter()
    let manager = NotificationManager(floatingPresenter: presenter)

    manager.send(title: "PowerShell", body: "body", sessionId: "session-1")

    XCTAssertEqual(
        presenter.messages,
        [
            .init(title: "PowerShell", body: "body", sessionId: "session-1")
        ]
    )
}
```

- [ ] **Step 2: Replace the obsolete initializer test with a single-path construction test**

Delete the current `testDefaultInitializerDoesNotTouchUserNotificationCenterBeforeAuthorizationRequest` and add this exact test:

```swift
func testDefaultInitializerSupportsFloatingOnlyNotificationManager() {
    XCTAssertNoThrow(
        _ = NotificationManager(
            floatingPresenter: RecordingFloatingNotificationPresenter()
        )
    )
}
```

- [ ] **Step 3: Remove obsolete dual-path stubs from the test file**

Delete these declarations from the bottom of the file because the new design will not use them:

```swift
private final class StubUserNotificationCenter: UserNotificationCenterProviding {
    weak var delegate: UNUserNotificationCenterDelegate?

    func requestAuthorization(
        options: UNAuthorizationOptions,
        completionHandler: @escaping @Sendable (Bool, (any Error)?) -> Void
    ) {
        completionHandler(false, nil)
    }

    func add(
        _ request: UNNotificationRequest,
        withCompletionHandler completionHandler: (@Sendable ((any Error)?) -> Void)?
    ) {
        completionHandler?(NSError(domain: "test", code: 0))
    }
}
```

Also delete the `import UserNotifications` line at the top of the file.

- [ ] **Step 4: Run the focused test target to verify the new tests fail for the right reason**

Run: `swift test --filter NotificationManagerFloatingFallbackTests`

Expected: FAIL with compile errors in `NotificationManagerFloatingFallbackTests.swift` because the old `NotificationManager` initializer still requires removed arguments like `notificationCenter` / `bundleInspector`, or because `NotificationManager` still exposes dual-path APIs the tests no longer reference.

- [ ] **Step 5: Commit the red test changes**

```bash
git add Tests/PowerShellTests/NotificationManagerFloatingFallbackTests.swift
git commit -m "test: define single-path notification routing"
```

## Task 2: Implement single-path floating notification routing

**Files:**
- Modify: `Sources/PowerShell/Services/NotificationManager.swift`
- Test: `Tests/PowerShellTests/NotificationManagerFloatingFallbackTests.swift`

- [ ] **Step 1: Remove system notification imports and protocols**

At the top of `Sources/PowerShell/Services/NotificationManager.swift`, replace the opening section:

```swift
import AppKit
import Foundation
import UserNotifications

protocol UserNotificationCenterProviding: AnyObject {
    var delegate: UNUserNotificationCenterDelegate? { get set }

    func requestAuthorization(
        options: UNAuthorizationOptions,
        completionHandler: @escaping @Sendable (Bool, (any Error)?) -> Void
    )

    func add(
        _ request: UNNotificationRequest,
        withCompletionHandler completionHandler: (@Sendable ((any Error)?) -> Void)?
    )
}

extension UNUserNotificationCenter: UserNotificationCenterProviding {}
```

with:

```swift
import Foundation
```

- [ ] **Step 2: Replace the stored properties and initializer with a floating-only model**

Inside `NotificationManager`, replace the property and initializer block:

```swift
    private var authorizationGranted = false
    private var notificationCenter: UserNotificationCenterProviding?
    private let notificationCenterFactory: () -> UserNotificationCenterProviding
    private let bundleInspector: () -> Bool
    private let floatingPresenter: FloatingNotificationPresenting

    private var isAppBundle: Bool {
        bundleInspector()
    }

    private var canUseUNNotifications: Bool {
        isAppBundle && authorizationGranted
    }

    init(
        notificationCenter: UserNotificationCenterProviding? = nil,
        notificationCenterFactory: @escaping () -> UserNotificationCenterProviding = { UNUserNotificationCenter.current() },
        bundleInspector: @escaping () -> Bool = { Bundle.main.bundleURL.pathExtension == "app" },
        floatingPresenter: FloatingNotificationPresenting = FloatingNotificationPanelPresenter()
    ) {
        self.notificationCenter = notificationCenter
        self.notificationCenterFactory = notificationCenterFactory
        self.bundleInspector = bundleInspector
        self.floatingPresenter = floatingPresenter
        super.init()
        configureFloatingPresenterCallbacks()
    }
```

with:

```swift
    private let floatingPresenter: FloatingNotificationPresenting

    init(
        floatingPresenter: FloatingNotificationPresenting = FloatingNotificationPanelPresenter()
    ) {
        self.floatingPresenter = floatingPresenter
        super.init()
        configureFloatingPresenterCallbacks()
    }
```

- [ ] **Step 3: Replace dual-path send logic with a single floating route**

Delete `requestAuthorization()`, `sendUNNotification(...)`, and `resolvedNotificationCenter()`. Then replace `send(title:body:sessionId:)`:

```swift
    func send(title: String, body: String, sessionId: String) {
        DebugLog.write("[NotificationManager] send: title=\(title), useUN=\(canUseUNNotifications)")
        if canUseUNNotifications {
            sendUNNotification(title: title, body: body, sessionId: sessionId)
        } else {
            floatingPresenter.show(title: title, body: body, sessionId: sessionId)
        }
    }
```

with:

```swift
    func send(title: String, body: String, sessionId: String) {
        DebugLog.write("[NotificationManager] send: title=\(title), presenter=floating")
        floatingPresenter.show(title: title, body: body, sessionId: sessionId)
    }
```

- [ ] **Step 4: Remove the obsolete system notification delegate extension**

Delete this entire block from the bottom of the file:

```swift
// MARK: - UNUserNotificationCenterDelegate

extension NotificationManager: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let sessionId = response.notification.request.content.userInfo["sessionId"] as? String
        if let sessionId {
            await MainActor.run {
                onNotificationClicked?(sessionId)
            }
        }
    }
}
```

- [ ] **Step 5: Run the focused notification tests to verify they pass**

Run: `swift test --filter NotificationManagerFloatingFallbackTests`

Expected: PASS, with `testSendAlwaysUsesFloatingPresenter`, `testDefaultInitializerSupportsFloatingOnlyNotificationManager`, and the existing panel interaction tests all green.

- [ ] **Step 6: Commit the implementation**

```bash
git add Sources/PowerShell/Services/NotificationManager.swift Tests/PowerShellTests/NotificationManagerFloatingFallbackTests.swift
git commit -m "refactor: unify notifications through floating panels"
```

## Task 3: Remove startup permission requests

**Files:**
- Modify: `Sources/PowerShell/App/PowerShellApp.swift:188-191`
- Test via build: `swift test --filter NotificationManagerFloatingFallbackTests`

- [ ] **Step 1: Delete the startup authorization request**

Inside the `.task` block in `RootContentView`, change:

```swift
        .task {
            llmService.loadSavedConfig()
            NotificationManager.shared.requestAuthorization()
            NotificationManager.shared.onNotificationClicked = { sessionIdString in
```

to:

```swift
        .task {
            llmService.loadSavedConfig()
            NotificationManager.shared.onNotificationClicked = { sessionIdString in
```

- [ ] **Step 2: Run the same notification test target to verify compile/runtime behavior stays green**

Run: `swift test --filter NotificationManagerFloatingFallbackTests`

Expected: PASS, confirming there are no remaining references to `requestAuthorization()` in app startup code.

- [ ] **Step 3: Commit the startup cleanup**

```bash
git add Sources/PowerShell/App/PowerShellApp.swift
git commit -m "refactor: stop requesting system notifications"
```

## Task 4: Update notification documentation to match the new architecture

**Files:**
- Modify: `feature/trd/notification.md`

- [ ] **Step 1: Rewrite the channel overview section**

In `feature/trd/notification.md`, replace this block:

```md
**3. 双通道通知降级**

```
App Bundle + 通知授权已授予 → UNUserNotificationCenter（原生 macOS 通知横幅）
App Bundle + 通知授权被拒绝 → FloatingNotificationBanner（右上角浮窗）
非 App Bundle（swift run）  → FloatingNotificationBanner（右上角浮窗）
```

`UNUserNotificationCenter` 在非 App Bundle 环境下调用会 crash（`bundleProxyForCurrentProcess is nil`），必须在调用前检查 bundle 类型。授权被拒绝时 `add()` 静默丢弃通知，因此需要缓存授权状态并在被拒时降级到浮窗。
```

with:

```md
**3. 统一应用内浮窗通知**

```
所有运行形态（debug / App Bundle / DMG） → FloatingNotificationBanner（右上角浮窗）
```

当前通知统一通过应用内浮窗展示，不再请求或依赖 macOS 系统通知权限，也不再根据 bundle 形态或授权结果切换通知通道。
```

- [ ] **Step 2: Rewrite the NotificationManager section**

Replace the subsection beginning at `### 4.3 NotificationManager — 双通道通知` with this content:

```md
### 4.3 NotificationManager — 统一浮窗通知入口

**文件**：`Sources/PowerShell/Services/NotificationManager.swift`

- `send(title:body:sessionId:)` 是统一通知入口
- 内部始终将通知转给 `FloatingNotificationPresenting`
- 不再包含 `UNUserNotificationCenter`、授权缓存或 bundle 判断逻辑
- 浮窗点击后仍通过 `onNotificationClicked` 回调切换到对应终端

当前设计的目标是让 debug 与 DMG / App Bundle 启动时的通知行为完全一致，避免出现不同运行形态下通知样式不一致的问题。
```

- [ ] **Step 3: Remove obsolete system notification bullet points**

Delete the old subsection:

```md
#### 原生通知通道（UNUserNotificationCenter）

- 请求 `.alert` + `.sound` 授权
- 实现 `UNUserNotificationCenterDelegate`，前台通知展示为 `.banner, .sound`
- 通知 `userInfo` 携带 `sessionId`，点击时回调 `onNotificationClicked`
- 必须在 App Bundle 环境下使用，且授权已通过
```

Delete the old subsection:

```md
#### 授权状态缓存

```swift
private var authorizationGranted = false

private var canUseUNNotifications: Bool {
    isAppBundle && authorizationGranted
}
```

`requestAuthorization()` 在非 App Bundle 环境下直接跳过（避免 crash），授权结果缓存到 `authorizationGranted`，`send()` 据此选择通知通道。
```

Keep the floating notification subsection, but make sure it reads as the primary path instead of a fallback path.

- [ ] **Step 4: Run a focused grep to verify the doc no longer describes the removed architecture**

Run: `grep -n "UNUserNotificationCenter\|authorizationGranted\|双通道通知降级" feature/trd/notification.md`

Expected: no matches.

- [ ] **Step 5: Commit the doc update**

```bash
git add feature/trd/notification.md
git commit -m "docs: update notification architecture"
```

## Task 5: Run final verification for the unified notification path

**Files:**
- Verify: `Sources/PowerShell/Services/NotificationManager.swift`
- Verify: `Sources/PowerShell/App/PowerShellApp.swift`
- Verify: `Tests/PowerShellTests/NotificationManagerFloatingFallbackTests.swift`
- Verify: `feature/trd/notification.md`

- [ ] **Step 1: Run the focused notification tests**

Run: `swift test --filter NotificationManagerFloatingFallbackTests`

Expected: PASS.

- [ ] **Step 2: Run the broader floating notification regression tests**

Run: `swift test --filter 'FloatingNotificationCenterTests|FloatingNotificationLayoutTests|NotificationManagerFloatingFallbackTests'`

Expected: PASS, confirming the route change did not break queueing, layout, or click handling.

- [ ] **Step 3: Build the app to catch integration errors**

Run: `swift build`

Expected: BUILD SUCCEEDED / exit code 0.

- [ ] **Step 4: Manually verify both launch modes use the same in-app floating panel**

Run these separately in a macOS GUI session and trigger one Claude hook notification in each build:

```bash
swift build && .build/debug/PowerShell
./Scripts/build_dmg.sh && open dist/PowerShell.app
```

Expected in both launches:

- Notification appears as the existing top-right in-app floating panel
- No macOS system notification permission prompt appears
- Clicking the panel opens the target session
- Closing the panel dismisses it without switching sessions

- [ ] **Step 5: Commit the verification-complete branch state**

```bash
git add Sources/PowerShell/Services/NotificationManager.swift Sources/PowerShell/App/PowerShellApp.swift Tests/PowerShellTests/NotificationManagerFloatingFallbackTests.swift feature/trd/notification.md
git commit -m "test: verify unified in-app notifications"
```
