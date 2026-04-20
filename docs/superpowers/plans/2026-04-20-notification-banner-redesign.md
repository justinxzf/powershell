# Notification Banner Aggregation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rework debug floating notifications so each terminal session has exactly one card showing the latest message, unlimited cards can stack, and clicking a card jumps to that session and clears the card.

**Architecture:** Replace the current per-notification overflow queue with a per-session aggregation model in `FloatingNotificationCenter`. Keep `NotificationManager` as the stable entry point, and simplify `FloatingNotificationPanels` so it renders only session cards with footer counts instead of overflow summary cards. Verification stays focused on state transitions, layout behavior, and click/close semantics.

**Tech Stack:** Swift 6, AppKit `NSPanel`, XCTest, Swift Package Manager

---

## File Structure

- Modify: `Sources/PowerShell/Services/FloatingNotificationCenter.swift`
  - Replace per-notification/overflow state with per-session aggregated card state and ordered presentations.
- Modify: `Sources/PowerShell/Services/FloatingNotificationPanels.swift`
  - Remove summary-card rendering and overflow actions; render only session cards and preserve click-to-open / close behavior.
- Modify: `Tests/PowerShellTests/FloatingNotificationCenterTests.swift`
  - Replace overflow-oriented tests with aggregation, ordering, dismissal, and unlimited-card tests.
- Modify: `Tests/PowerShellTests/FloatingNotificationLayoutTests.swift`
  - Replace summary-height assumptions with tests that prove cards keep stacking beyond three items.
- Modify: `Tests/PowerShellTests/NotificationManagerFloatingFallbackTests.swift`
  - Keep fallback coverage and add presenter-level interaction coverage only if the production API changes.

### Task 1: Rebuild notification state around session aggregation

**Files:**
- Modify: `Sources/PowerShell/Services/FloatingNotificationCenter.swift:1-139`
- Test: `Tests/PowerShellTests/FloatingNotificationCenterTests.swift`

- [ ] **Step 1: Write the failing test for same-session aggregation**

```swift
func testEnqueueingMultipleNotificationsForSameSessionKeepsSingleCardWithLatestContent() {
    let center = FloatingNotificationCenter()

    center.enqueue(title: "first", body: "body-1", sessionId: "s1")
    center.enqueue(title: "second", body: "body-2", sessionId: "s1")

    XCTAssertEqual(
        center.presentations(),
        [
            .card(title: "second", body: "body-2", sessionId: "s1", footer: "还有 1 条")
        ]
    )
}
```

- [ ] **Step 2: Run the test to verify it fails for the expected reason**

Run: `swift test --filter FloatingNotificationCenterTests/testEnqueueingMultipleNotificationsForSameSessionKeepsSingleCardWithLatestContent`
Expected: FAIL because `presentations()` currently returns two cards or an overflow summary instead of one aggregated card.

- [ ] **Step 3: Write the minimal aggregation model in `FloatingNotificationCenter`**

```swift
@MainActor
final class FloatingNotificationCenter {
    struct Presentation: Equatable {
        let title: String
        let body: String
        let sessionId: String
        let footer: String?
    }

    private struct SessionNotification: Equatable {
        let sessionId: String
        var title: String
        var body: String
        var messageCount: Int
        var lastUpdatedAt: Int
    }

    private var sessions: [SessionNotification] = []
    private var updateSequence = 0

    func enqueue(title: String, body: String, sessionId: String) {
        updateSequence += 1

        if let index = sessions.firstIndex(where: { $0.sessionId == sessionId }) {
            sessions[index].title = title
            sessions[index].body = body
            sessions[index].messageCount += 1
            sessions[index].lastUpdatedAt = updateSequence
        } else {
            sessions.append(
                SessionNotification(
                    sessionId: sessionId,
                    title: title,
                    body: body,
                    messageCount: 1,
                    lastUpdatedAt: updateSequence
                )
            )
        }

        sessions.sort { $0.lastUpdatedAt > $1.lastUpdatedAt }
    }

    func dismiss(sessionId: String) {
        sessions.removeAll { $0.sessionId == sessionId }
    }

    func presentations() -> [Presentation] {
        sessions.map { session in
            Presentation(
                title: session.title,
                body: session.body,
                sessionId: session.sessionId,
                footer: session.messageCount > 1 ? "还有 \(session.messageCount - 1) 条" : nil
            )
        }
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --filter FloatingNotificationCenterTests/testEnqueueingMultipleNotificationsForSameSessionKeepsSingleCardWithLatestContent`
Expected: PASS

- [ ] **Step 5: Add the next failing tests for ordering and dismissal semantics**

```swift
func testNewNotificationMovesExistingSessionCardToTop() {
    let center = FloatingNotificationCenter()

    center.enqueue(title: "one", body: "body-1", sessionId: "s1")
    center.enqueue(title: "two", body: "body-2", sessionId: "s2")
    center.enqueue(title: "three", body: "body-3", sessionId: "s1")

    XCTAssertEqual(
        center.presentations(),
        [
            .card(title: "three", body: "body-3", sessionId: "s1", footer: "还有 1 条"),
            .card(title: "two", body: "body-2", sessionId: "s2", footer: nil)
        ]
    )
}

func testDismissRemovesEntireSessionCard() {
    let center = FloatingNotificationCenter()

    center.enqueue(title: "one", body: "body-1", sessionId: "s1")
    center.enqueue(title: "two", body: "body-2", sessionId: "s1")
    center.enqueue(title: "three", body: "body-3", sessionId: "s2")

    center.dismiss(sessionId: "s1")

    XCTAssertEqual(
        center.presentations(),
        [
            .card(title: "three", body: "body-3", sessionId: "s2", footer: nil)
        ]
    )
}
```

- [ ] **Step 6: Run the two new tests to verify they fail**

Run: `swift test --filter FloatingNotificationCenterTests`
Expected: FAIL because dismissal currently uses notification IDs and ordering logic is not session-based yet.

- [ ] **Step 7: Update the production API and implementations minimally**

```swift
enum Presentation: Equatable {
    case card(title: String, body: String, sessionId: String, footer: String?)
}

func dismiss(sessionId: String) {
    sessions.removeAll { $0.sessionId == sessionId }
}

func presentations() -> [Presentation] {
    sessions.map { session in
        .card(
            title: session.title,
            body: session.body,
            sessionId: session.sessionId,
            footer: session.messageCount > 1 ? "还有 \(session.messageCount - 1) 条" : nil
        )
    }
}
```

- [ ] **Step 8: Run the full center test file to verify it passes**

Run: `swift test --filter FloatingNotificationCenterTests`
Expected: PASS with the aggregation, ordering, and dismissal tests all green.

- [ ] **Step 9: Commit the center refactor**

```bash
git add Tests/PowerShellTests/FloatingNotificationCenterTests.swift Sources/PowerShell/Services/FloatingNotificationCenter.swift
git commit -m "refactor: aggregate floating notifications by session"
```

### Task 2: Remove overflow UI and switch panels to session-card interactions

**Files:**
- Modify: `Sources/PowerShell/Services/FloatingNotificationPanels.swift:1-294`
- Test: `Tests/PowerShellTests/NotificationManagerFloatingFallbackTests.swift`

- [ ] **Step 1: Write the failing test for click-to-clear session behavior at the presenter boundary**

```swift
func testOpeningCardDismissesSessionAndInvokesSelectionHandler() {
    let center = FloatingNotificationCenter()
    center.enqueue(title: "one", body: "body-1", sessionId: "s1")

    let presenter = FloatingNotificationPanelPresenter(center: center)
    var openedSessionID: String?
    presenter.onOpenSession = { openedSessionID = $0 }

    presenter.handleTestingAction(.open(sessionId: "s1"))

    XCTAssertEqual(openedSessionID, "s1")
    XCTAssertTrue(center.presentations().isEmpty)
}
```

- [ ] **Step 2: Run the test to verify it fails for a real missing API**

Run: `swift test --filter NotificationManagerFloatingFallbackTests/testOpeningCardDismissesSessionAndInvokesSelectionHandler`
Expected: FAIL because `FloatingNotificationPanelPresenter` does not expose an injectable open handler or a session-based action surface.

- [ ] **Step 3: Add the minimal presenter action surface needed for session-based dismissal**

```swift
@MainActor
final class FloatingNotificationPanelPresenter: FloatingNotificationPresenting {
    var onOpenSession: ((String) -> Void)?

    private func handlePanelAction(_ action: FloatingNotificationPanelAction) {
        switch action {
        case .open(let sessionId):
            center.dismiss(sessionId: sessionId)
            onOpenSession?(sessionId)
        case .close(let sessionId):
            center.dismiss(sessionId: sessionId)
        }

        render()
    }
}

private enum FloatingNotificationPanelAction {
    case open(sessionId: String)
    case close(sessionId: String)
}
```

- [ ] **Step 4: Run the targeted presenter test to verify it passes**

Run: `swift test --filter NotificationManagerFloatingFallbackTests/testOpeningCardDismissesSessionAndInvokesSelectionHandler`
Expected: PASS

- [ ] **Step 5: Remove overflow-only rendering branches from the panel view**

```swift
func configure(
    sessionId: String,
    title: String,
    body: String,
    footer: String?,
    onAction: @escaping (FloatingNotificationPanelAction) -> Void
) {
    self.sessionId = sessionId
    self.onAction = onAction
    titleField.stringValue = title
    bodyField.stringValue = body
    footerField.stringValue = footer ?? ""
    footerField.isHidden = footer == nil
    closeButton.isHidden = false
    needsLayout = true
}

override func mouseDown(with event: NSEvent) {
    guard let sessionId else { return }
    onAction?(.open(sessionId: sessionId))
}

@objc private func closeTapped() {
    guard let sessionId else { return }
    onAction?(.close(sessionId: sessionId))
}
```

- [ ] **Step 6: Run the notification fallback tests to verify the simplified presenter still integrates correctly**

Run: `swift test --filter NotificationManagerFloatingFallbackTests`
Expected: PASS

- [ ] **Step 7: Wire the app callback through `NotificationManager` instead of `NotificationManager.shared` inside the presenter**

```swift
init(
    notificationCenter: UserNotificationCenterProviding? = nil,
    notificationCenterFactory: @escaping () -> UserNotificationCenterProviding = { UNUserNotificationCenter.current() },
    bundleInspector: @escaping () -> Bool = { Bundle.main.bundleURL.pathExtension == "app" },
    floatingPresenter: FloatingNotificationPresenting? = nil
) {
    let presenter = floatingPresenter ?? FloatingNotificationPanelPresenter()
    self.floatingPresenter = presenter
    super.init()

    if let presenter = presenter as? FloatingNotificationPanelPresenter {
        presenter.onOpenSession = { [weak self] sessionId in
            self?.onNotificationClicked?(sessionId)
        }
    }
}
```

- [ ] **Step 8: Run the presenter-related tests again to confirm the callback wiring stays green**

Run: `swift test --filter NotificationManagerFloatingFallbackTests`
Expected: PASS

- [ ] **Step 9: Commit the panel simplification**

```bash
git add Sources/PowerShell/Services/FloatingNotificationPanels.swift Sources/PowerShell/Services/NotificationManager.swift Tests/PowerShellTests/NotificationManagerFloatingFallbackTests.swift
git commit -m "refactor: simplify floating notification panels"
```

### Task 3: Update layout tests for unlimited card stacking

**Files:**
- Modify: `Tests/PowerShellTests/FloatingNotificationLayoutTests.swift:1-84`
- Test: `Tests/PowerShellTests/FloatingNotificationLayoutTests.swift`

- [ ] **Step 1: Write the failing test for a fourth and fifth card continuing downward**

```swift
func testCardsContinueStackingBeyondThreeItems() {
    let layout = FloatingNotificationLayout(
        cardWidth: 320,
        cardHeight: 92,
        summaryHeight: 84,
        topInset: 12,
        rightInset: 12,
        spacing: 10
    )

    let frames = layout.frames(
        for: [
            .card(title: "one", body: "body-1", sessionId: "s1", footer: nil),
            .card(title: "two", body: "body-2", sessionId: "s2", footer: nil),
            .card(title: "three", body: "body-3", sessionId: "s3", footer: nil),
            .card(title: "four", body: "body-4", sessionId: "s4", footer: nil),
            .card(title: "five", body: "body-5", sessionId: "s5", footer: nil)
        ],
        visibleFrame: NSRect(x: 0, y: 0, width: 1440, height: 900)
    )

    XCTAssertEqual(
        frames,
        [
            NSRect(x: 1108, y: 796, width: 320, height: 92),
            NSRect(x: 1108, y: 694, width: 320, height: 92),
            NSRect(x: 1108, y: 592, width: 320, height: 92),
            NSRect(x: 1108, y: 490, width: 320, height: 92),
            NSRect(x: 1108, y: 388, width: 320, height: 92)
        ]
    )
}
```

- [ ] **Step 2: Run the layout tests to verify the new expectation fails first**

Run: `swift test --filter FloatingNotificationLayoutTests`
Expected: FAIL because existing tests and production assumptions still cover summary-card layout instead of unlimited card stacking.

- [ ] **Step 3: Remove summary-specific expectations from the test file and keep only card stacking coverage**

```swift
func testFramesStackFromTopRightWithFixedSpacing() {
    let layout = FloatingNotificationLayout(
        cardWidth: 320,
        cardHeight: 92,
        summaryHeight: 84,
        topInset: 12,
        rightInset: 12,
        spacing: 10
    )

    let frames = layout.frames(
        for: [
            .card(title: "one", body: "body-1", sessionId: "s1", footer: nil),
            .card(title: "two", body: "body-2", sessionId: "s2", footer: nil),
            .card(title: "three", body: "body-3", sessionId: "s3", footer: nil)
        ],
        visibleFrame: NSRect(x: 0, y: 0, width: 1440, height: 900)
    )

    XCTAssertEqual(
        frames,
        [
            NSRect(x: 1108, y: 796, width: 320, height: 92),
            NSRect(x: 1108, y: 694, width: 320, height: 92),
            NSRect(x: 1108, y: 592, width: 320, height: 92)
        ]
    )
}
```

- [ ] **Step 4: Run the layout tests to verify they pass**

Run: `swift test --filter FloatingNotificationLayoutTests`
Expected: PASS

- [ ] **Step 5: Commit the layout verification update**

```bash
git add Tests/PowerShellTests/FloatingNotificationLayoutTests.swift
git commit -m "test: cover unlimited notification card stacking"
```

### Task 4: Run final verification for the revised notification flow

**Files:**
- Modify: `Sources/PowerShell/Services/FloatingNotificationCenter.swift`
- Modify: `Sources/PowerShell/Services/FloatingNotificationPanels.swift`
- Modify: `Sources/PowerShell/Services/NotificationManager.swift`
- Modify: `Tests/PowerShellTests/FloatingNotificationCenterTests.swift`
- Modify: `Tests/PowerShellTests/FloatingNotificationLayoutTests.swift`
- Modify: `Tests/PowerShellTests/NotificationManagerFloatingFallbackTests.swift`

- [ ] **Step 1: Run the focused notification test suite**

Run: `swift test --filter FloatingNotificationCenterTests && swift test --filter FloatingNotificationLayoutTests && swift test --filter NotificationManagerFloatingFallbackTests`
Expected: PASS for all three test groups.

- [ ] **Step 2: Run the package build**

Run: `swift build`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Smoke test the app startup path**

Run: `swift run PowerShell`
Expected: app starts without the previous `UNUserNotificationCenter.current()` crash.

- [ ] **Step 4: Verify the revised behavior manually**

Run these manual checks in the app:

```text
1. Trigger multiple notifications from the same terminal and confirm only one card remains for that session.
2. Confirm the card title/body always show the newest notification content.
3. Confirm the footer shows "还有 N 条" when the same session has additional pending notifications.
4. Trigger notifications from four or more different terminals and confirm all cards continue stacking downward.
5. Click a card and confirm the app jumps to that session and removes the card.
6. Click the close button and confirm the card disappears without switching terminals.
```

Expected: all six checks succeed.

- [ ] **Step 5: Commit the finished behavior changes**

```bash
git add Sources/PowerShell/Services/FloatingNotificationCenter.swift Sources/PowerShell/Services/FloatingNotificationPanels.swift Sources/PowerShell/Services/NotificationManager.swift Tests/PowerShellTests/FloatingNotificationCenterTests.swift Tests/PowerShellTests/FloatingNotificationLayoutTests.swift Tests/PowerShellTests/NotificationManagerFloatingFallbackTests.swift
git commit -m "feat: aggregate floating notifications by terminal"
```
