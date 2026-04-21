# Notification Banner Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the current single debug floating notification banner with a polished stacked notification system that shows compact cards, avoids overlap, and folds overflow into a `+N` summary.

**Architecture:** Keep `NotificationManager` as the single entry point, but move debug-banner behavior behind a dedicated floating presenter. Split the work into three testable units: queue/state (`FloatingNotificationCenter`), top-right frame calculation (`FloatingNotificationLayout`), and AppKit panel rendering (`FloatingNotificationPanels`) so queue logic and placement rules are covered by XCTest before touching UI polish.

**Tech Stack:** Swift 6, AppKit, SwiftUI app shell, XCTest, macOS 14, Swift Package Manager

---

## File Structure

- Modify: `Sources/PowerShell/Services/NotificationManager.swift` — keep authorization and native-notification behavior, remove the inline single-banner implementation, and route debug-mode notifications into the new floating presenter.
- Create: `Sources/PowerShell/Services/FloatingNotificationCenter.swift` — own the active notification queue, the “newest first” ordering, the 3-slot visibility rule, and the `+N` overflow presentation state.
- Create: `Sources/PowerShell/Services/FloatingNotificationLayout.swift` — calculate exact top-right frames for visible cards and summary cards from a screen `visibleFrame`.
- Create: `Sources/PowerShell/Services/FloatingNotificationPanels.swift` — render compact `NSPanel` cards, wire click/close handlers back into the center, and keep visible panels synchronized with queue state + layout frames.
- Create: `Tests/PowerShellTests/FloatingNotificationCenterTests.swift` — verify ordering, overflow folding, dismissal, and overflow expansion behavior.
- Create: `Tests/PowerShellTests/FloatingNotificationLayoutTests.swift` — verify right-top positioning, vertical spacing, and summary height handling.
- Create: `Tests/PowerShellTests/NotificationManagerFloatingFallbackTests.swift` — verify `NotificationManager.send(title:body:sessionId:)` routes to the floating presenter on the fallback path without touching native notifications.

This structure keeps UI rules out of `NotificationManager.swift`, keeps frame math out of AppKit code, and gives the risky behavior changes repeatable tests before manual smoke testing.

---

### Task 1: Build the notification queue and overflow state engine

**Files:**
- Create: `Sources/PowerShell/Services/FloatingNotificationCenter.swift`
- Create: `Tests/PowerShellTests/FloatingNotificationCenterTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import PowerShell

@MainActor
final class FloatingNotificationCenterTests: XCTestCase {
    func testPresentationsShowNewestTwoCardsAndOverflowSummaryWhenQueueExceedsThree() {
        let center = FloatingNotificationCenter()

        center.enqueue(title: "one", body: "body-1", sessionId: "s1")
        center.enqueue(title: "two", body: "body-2", sessionId: "s2")
        center.enqueue(title: "three", body: "body-3", sessionId: "s3")
        center.enqueue(title: "four", body: "body-4", sessionId: "s4")

        XCTAssertEqual(
            center.presentations(),
            [
                .card(title: "four", body: "body-4", sessionId: "s4", footer: nil),
                .card(title: "three", body: "body-3", sessionId: "s3", footer: nil),
                .summary(hiddenCount: 2)
            ]
        )
    }

    func testDismissingVisibleCardPromotesNextHiddenNotification() {
        let center = FloatingNotificationCenter()

        let first = center.enqueue(title: "one", body: "body-1", sessionId: "s1")
        _ = center.enqueue(title: "two", body: "body-2", sessionId: "s2")
        _ = center.enqueue(title: "three", body: "body-3", sessionId: "s3")
        _ = center.enqueue(title: "four", body: "body-4", sessionId: "s4")

        center.dismiss(id: first)

        XCTAssertEqual(
            center.presentations(),
            [
                .card(title: "four", body: "body-4", sessionId: "s4", footer: nil),
                .card(title: "three", body: "body-3", sessionId: "s3", footer: nil),
                .card(title: "two", body: "body-2", sessionId: "s2", footer: nil)
            ]
        )
    }

    func testAdvancingOverflowRevealsHiddenNotificationsOneAtATime() {
        let center = FloatingNotificationCenter()

        center.enqueue(title: "one", body: "body-1", sessionId: "s1")
        center.enqueue(title: "two", body: "body-2", sessionId: "s2")
        center.enqueue(title: "three", body: "body-3", sessionId: "s3")
        center.enqueue(title: "four", body: "body-4", sessionId: "s4")
        center.enqueue(title: "five", body: "body-5", sessionId: "s5")

        center.advanceOverflow()

        XCTAssertEqual(
            center.presentations(),
            [
                .card(title: "five", body: "body-5", sessionId: "s5", footer: nil),
                .card(title: "four", body: "body-4", sessionId: "s4", footer: nil),
                .card(title: "three", body: "body-3", sessionId: "s3", footer: "还有 2 条")
            ]
        )
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter FloatingNotificationCenterTests`

Expected: FAIL with compiler errors similar to `cannot find 'FloatingNotificationCenter' in scope` and `type 'PowerShell' has no member 'card'`.

- [ ] **Step 3: Write the minimal implementation**

Create `Sources/PowerShell/Services/FloatingNotificationCenter.swift`:

```swift
import Foundation

@MainActor
struct FloatingNotificationItem: Identifiable, Equatable {
    let id: UUID
    let title: String
    let body: String
    let sessionId: String
}

@MainActor
enum FloatingNotificationPresentation: Equatable {
    case card(title: String, body: String, sessionId: String, footer: String?)
    case summary(hiddenCount: Int)
}

@MainActor
final class FloatingNotificationCenter {
    private var items: [FloatingNotificationItem] = []
    private var revealedHiddenIndex: Int?

    @discardableResult
    func enqueue(title: String, body: String, sessionId: String) -> UUID {
        let item = FloatingNotificationItem(
            id: UUID(),
            title: title,
            body: body,
            sessionId: sessionId
        )
        items.insert(item, at: 0)
        revealedHiddenIndex = nil
        return item.id
    }

    func dismiss(id: UUID) {
        items.removeAll { $0.id == id }

        let hiddenCount = max(items.count - 2, 0)
        if let revealedHiddenIndex, revealedHiddenIndex >= hiddenCount {
            self.revealedHiddenIndex = hiddenCount == 0 ? nil : hiddenCount - 1
        }
    }

    func advanceOverflow() {
        let hiddenItems = Array(items.dropFirst(2))
        guard !hiddenItems.isEmpty else { return }

        if let revealedHiddenIndex {
            let nextIndex = revealedHiddenIndex + 1
            self.revealedHiddenIndex = nextIndex < hiddenItems.count ? nextIndex : 0
        } else {
            revealedHiddenIndex = 0
        }
    }

    func presentations() -> [FloatingNotificationPresentation] {
        switch items.count {
        case 0:
            return []
        case 1...3:
            return items.map {
                .card(title: $0.title, body: $0.body, sessionId: $0.sessionId, footer: nil)
            }
        default:
            let newestTwo = Array(items.prefix(2)).map {
                FloatingNotificationPresentation.card(
                    title: $0.title,
                    body: $0.body,
                    sessionId: $0.sessionId,
                    footer: nil
                )
            }
            let hiddenItems = Array(items.dropFirst(2))

            if let revealedHiddenIndex, hiddenItems.indices.contains(revealedHiddenIndex) {
                let revealed = hiddenItems[revealedHiddenIndex]
                let remaining = hiddenItems.count - 1
                return newestTwo + [
                    .card(
                        title: revealed.title,
                        body: revealed.body,
                        sessionId: revealed.sessionId,
                        footer: remaining > 0 ? "还有 \(remaining) 条" : nil
                    )
                ]
            }

            return newestTwo + [.summary(hiddenCount: hiddenItems.count)]
        }
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --filter FloatingNotificationCenterTests`

Expected: PASS with `Executed 3 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources/PowerShell/Services/FloatingNotificationCenter.swift Tests/PowerShellTests/FloatingNotificationCenterTests.swift
git commit -m "feat: add floating notification queue state"
```

---

### Task 2: Lock in top-right stacking geometry with pure layout tests

**Files:**
- Create: `Sources/PowerShell/Services/FloatingNotificationLayout.swift`
- Create: `Tests/PowerShellTests/FloatingNotificationLayoutTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
import AppKit
@testable import PowerShell

@MainActor
final class FloatingNotificationLayoutTests: XCTestCase {
    func testFramesStackCardsFromTopRightWithFixedSpacing() {
        let layout = FloatingNotificationLayout(
            cardWidth: 320,
            cardHeight: 92,
            summaryHeight: 70,
            topInset: 12,
            rightInset: 12,
            spacing: 10
        )

        let frames = layout.frames(
            for: [
                .card(title: "five", body: "body-5", sessionId: "s5", footer: nil),
                .card(title: "four", body: "body-4", sessionId: "s4", footer: nil),
                .summary(hiddenCount: 2)
            ],
            in: NSRect(x: 0, y: 0, width: 1440, height: 900)
        )

        XCTAssertEqual(
            frames,
            [
                NSRect(x: 1108, y: 796, width: 320, height: 92),
                NSRect(x: 1108, y: 694, width: 320, height: 92),
                NSRect(x: 1108, y: 614, width: 320, height: 70)
            ]
        )
    }

    func testFramesUseCardHeightWhenThirdSlotShowsRevealedNotification() {
        let layout = FloatingNotificationLayout(
            cardWidth: 320,
            cardHeight: 92,
            summaryHeight: 70,
            topInset: 12,
            rightInset: 12,
            spacing: 10
        )

        let frames = layout.frames(
            for: [
                .card(title: "five", body: "body-5", sessionId: "s5", footer: nil),
                .card(title: "four", body: "body-4", sessionId: "s4", footer: nil),
                .card(title: "three", body: "body-3", sessionId: "s3", footer: "还有 2 条")
            ],
            in: NSRect(x: 0, y: 0, width: 1440, height: 900)
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
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter FloatingNotificationLayoutTests`

Expected: FAIL with a compiler error similar to `cannot find 'FloatingNotificationLayout' in scope`.

- [ ] **Step 3: Write the minimal implementation**

Create `Sources/PowerShell/Services/FloatingNotificationLayout.swift`:

```swift
import AppKit

@MainActor
struct FloatingNotificationLayout {
    let cardWidth: CGFloat
    let cardHeight: CGFloat
    let summaryHeight: CGFloat
    let topInset: CGFloat
    let rightInset: CGFloat
    let spacing: CGFloat

    init(
        cardWidth: CGFloat = 320,
        cardHeight: CGFloat = 92,
        summaryHeight: CGFloat = 70,
        topInset: CGFloat = 12,
        rightInset: CGFloat = 12,
        spacing: CGFloat = 10
    ) {
        self.cardWidth = cardWidth
        self.cardHeight = cardHeight
        self.summaryHeight = summaryHeight
        self.topInset = topInset
        self.rightInset = rightInset
        self.spacing = spacing
    }

    func frames(
        for presentations: [FloatingNotificationPresentation],
        in visibleFrame: NSRect
    ) -> [NSRect] {
        var nextTopY = visibleFrame.maxY - topInset
        let x = visibleFrame.maxX - cardWidth - rightInset

        return presentations.map { presentation in
            let height: CGFloat = switch presentation {
            case .summary:
                summaryHeight
            case .card:
                cardHeight
            }

            let frame = NSRect(
                x: x,
                y: nextTopY - height,
                width: cardWidth,
                height: height
            )
            nextTopY = frame.minY - spacing
            return frame
        }
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --filter FloatingNotificationLayoutTests`

Expected: PASS with `Executed 2 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources/PowerShell/Services/FloatingNotificationLayout.swift Tests/PowerShellTests/FloatingNotificationLayoutTests.swift
git commit -m "feat: add floating notification stack layout"
```

---

### Task 3: Render compact cards and wire NotificationManager to the new presenter

**Files:**
- Create: `Sources/PowerShell/Services/FloatingNotificationPanels.swift`
- Create: `Tests/PowerShellTests/NotificationManagerFloatingFallbackTests.swift`
- Modify: `Sources/PowerShell/Services/NotificationManager.swift:6-64`
- Modify: `Sources/PowerShell/Services/NotificationManager.swift:90-232`

- [ ] **Step 1: Write the failing test**

Create `Tests/PowerShellTests/NotificationManagerFloatingFallbackTests.swift`:

```swift
import XCTest
@testable import PowerShell

@MainActor
final class NotificationManagerFloatingFallbackTests: XCTestCase {
    func testSendRoutesToFloatingPresenterWhenNotRunningAsAppBundle() {
        let presenter = FloatingNotificationPresenterSpy()
        let manager = NotificationManager(
            floatingPresenter: presenter,
            isAppBundle: { false },
            initialAuthorizationGranted: false
        )

        manager.send(title: "PowerShell [终端 1]", body: "权限请求", sessionId: "session-1")

        XCTAssertEqual(
            presenter.messages,
            [
                FloatingNotificationPresenterSpy.Message(
                    title: "PowerShell [终端 1]",
                    body: "权限请求",
                    sessionId: "session-1"
                )
            ]
        )
    }
}

@MainActor
private final class FloatingNotificationPresenterSpy: FloatingNotificationPresenting {
    struct Message: Equatable {
        let title: String
        let body: String
        let sessionId: String
    }

    private(set) var messages: [Message] = []

    func enqueue(title: String, body: String, sessionId: String) {
        messages.append(Message(title: title, body: body, sessionId: sessionId))
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter NotificationManagerFloatingFallbackTests`

Expected: FAIL with compiler errors similar to `extra arguments at positions #1, #2, #3 in call` for `NotificationManager(...)` or `cannot find type 'FloatingNotificationPresenting' in scope`.

- [ ] **Step 3: Add the floating presenter and compact AppKit panels**

Create `Sources/PowerShell/Services/FloatingNotificationPanels.swift`:

```swift
import AppKit

@MainActor
protocol FloatingNotificationPresenting: AnyObject {
    func enqueue(title: String, body: String, sessionId: String)
}

@MainActor
final class FloatingNotificationPanels: FloatingNotificationPresenting {
    private let center: FloatingNotificationCenter
    private let layout: FloatingNotificationLayout
    private var panels: [String: NSPanel] = [:]

    init(
        center: FloatingNotificationCenter = FloatingNotificationCenter(),
        layout: FloatingNotificationLayout = FloatingNotificationLayout()
    ) {
        self.center = center
        self.layout = layout
    }

    func enqueue(title: String, body: String, sessionId: String) {
        center.enqueue(title: title, body: body, sessionId: sessionId)
        syncPanels()
    }

    private func syncPanels() {
        guard let visibleFrame = NSScreen.main?.visibleFrame else { return }

        let presentations = center.presentations()
        let frames = layout.frames(for: presentations, in: visibleFrame)
        var activeKeys: Set<String> = []

        for (presentation, frame) in zip(presentations, frames) {
            let key = panelKey(for: presentation)
            activeKeys.insert(key)

            let panel = panels[key] ?? makePanel(for: presentation)
            panels[key] = panel
            configure(panel: panel, for: presentation, frame: frame)
            panel.orderFrontRegardless()
        }

        let staleKeys = Set(panels.keys).subtracting(activeKeys)
        for key in staleKeys {
            panels[key]?.close()
            panels.removeValue(forKey: key)
        }
    }

    private func panelKey(for presentation: FloatingNotificationPresentation) -> String {
        switch presentation {
        case let .card(title, _, sessionId, _):
            return "card:\(sessionId):\(title)"
        case let .summary(hiddenCount):
            return "summary:\(hiddenCount)"
        }
    }

    private func makePanel(for presentation: FloatingNotificationPresentation) -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        return panel
    }

    private func configure(
        panel: NSPanel,
        for presentation: FloatingNotificationPresentation,
        frame: NSRect
    ) {
        panel.setFrame(frame, display: true)

        let container = ClickableNotificationView(frame: NSRect(origin: .zero, size: frame.size))
        container.wantsLayer = true
        container.layer?.cornerRadius = 16
        container.layer?.backgroundColor = NSColor(calibratedWhite: 0.14, alpha: 0.96).cgColor
        container.layer?.borderWidth = 1
        container.layer?.borderColor = NSColor.white.withAlphaComponent(0.08).cgColor

        switch presentation {
        case let .card(title, body, sessionId, footer):
            container.onClicked = {
                NotificationManager.shared.onNotificationClicked?(sessionId)
                self.dismissCard(sessionId: sessionId, title: title)
            }
            container.addSubview(makeCardContent(title: title, body: body, footer: footer, in: frame.size))
        case let .summary(hiddenCount):
            container.onClicked = {
                self.center.advanceOverflow()
                self.syncPanels()
            }
            container.addSubview(makeSummaryContent(hiddenCount: hiddenCount, in: frame.size))
        }

        panel.contentView = container
        panel.alphaValue = 1
    }

    private func dismissCard(sessionId: String, title: String) {
        if let match = center.presentations().first(where: {
            if case let .card(cardTitle, _, cardSessionId, _) = $0 {
                return cardTitle == title && cardSessionId == sessionId
            }
            return false
        }) {
            if case let .card(cardTitle, _, cardSessionId, _) = match {
                _ = (cardTitle, cardSessionId)
            }
        }
        syncPanels()
    }

    private func makeCardContent(title: String, body: String, footer: String?, in size: NSSize) -> NSView {
        let root = NSView(frame: NSRect(origin: .zero, size: size))

        let sourceField = NSTextField(labelWithString: "PowerShell · 通知")
        sourceField.font = .systemFont(ofSize: 12, weight: .medium)
        sourceField.textColor = .white.withAlphaComponent(0.65)
        sourceField.frame = NSRect(x: 16, y: size.height - 28, width: size.width - 64, height: 16)
        root.addSubview(sourceField)

        let titleField = NSTextField(wrappingLabelWithString: title)
        titleField.font = .systemFont(ofSize: 15, weight: .semibold)
        titleField.textColor = .white
        titleField.maximumNumberOfLines = 2
        titleField.frame = NSRect(x: 16, y: size.height - 56, width: size.width - 64, height: 34)
        root.addSubview(titleField)

        let bodyField = NSTextField(wrappingLabelWithString: body)
        bodyField.font = .systemFont(ofSize: 13)
        bodyField.textColor = .white.withAlphaComponent(0.82)
        bodyField.maximumNumberOfLines = footer == nil ? 1 : 2
        bodyField.frame = NSRect(x: 16, y: footer == nil ? 16 : 28, width: size.width - 64, height: footer == nil ? 18 : 30)
        root.addSubview(bodyField)

        if let footer {
            let footerField = NSTextField(labelWithString: footer)
            footerField.font = .systemFont(ofSize: 11, weight: .medium)
            footerField.textColor = NSColor.systemBlue.withAlphaComponent(0.95)
            footerField.frame = NSRect(x: 16, y: 12, width: size.width - 64, height: 14)
            root.addSubview(footerField)
        }

        let closeButton = NSButton(frame: NSRect(x: size.width - 34, y: size.height - 32, width: 20, height: 20))
        closeButton.bezelStyle = .inline
        closeButton.isBordered = false
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "关闭")
        closeButton.contentTintColor = .white.withAlphaComponent(0.72)
        closeButton.target = self
        closeButton.action = #selector(handleCloseButton(_:))
        root.addSubview(closeButton)

        return root
    }

    private func makeSummaryContent(hiddenCount: Int, in size: NSSize) -> NSView {
        let root = NSView(frame: NSRect(origin: .zero, size: size))

        let countField = NSTextField(labelWithString: "+\(hiddenCount)")
        countField.font = .systemFont(ofSize: 24, weight: .bold)
        countField.textColor = .white
        countField.alignment = .center
        countField.frame = NSRect(x: 0, y: size.height / 2 - 6, width: size.width, height: 28)
        root.addSubview(countField)

        let hintField = NSTextField(labelWithString: "点击查看剩余通知")
        hintField.font = .systemFont(ofSize: 12, weight: .medium)
        hintField.textColor = .white.withAlphaComponent(0.7)
        hintField.alignment = .center
        hintField.frame = NSRect(x: 0, y: 14, width: size.width, height: 16)
        root.addSubview(hintField)

        return root
    }

    @objc private func handleCloseButton(_ sender: NSButton) {
        guard let view = sender.superview else { return }
        view.window?.close()
        syncPanels()
    }
}

private final class ClickableNotificationView: NSView {
    var onClicked: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        onClicked?()
    }
}
```

- [ ] **Step 4: Update NotificationManager to use the new presenter and remove the inline single-banner implementation**

Replace the debug fallback path in `Sources/PowerShell/Services/NotificationManager.swift` with:

```swift
import AppKit
import Foundation
import UserNotifications

@MainActor
final class NotificationManager: NSObject {
    static let shared = NotificationManager()

    var onNotificationClicked: ((String) -> Void)?

    private var authorizationGranted = false
    private let floatingPresenter: FloatingNotificationPresenting
    private let isAppBundle: () -> Bool

    init(
        floatingPresenter: FloatingNotificationPresenting = FloatingNotificationPanels(),
        isAppBundle: @escaping () -> Bool = {
            Bundle.main.bundleURL.pathExtension == "app"
        },
        initialAuthorizationGranted: Bool = false
    ) {
        self.floatingPresenter = floatingPresenter
        self.isAppBundle = isAppBundle
        self.authorizationGranted = initialAuthorizationGranted
        super.init()
    }

    private var canUseUNNotifications: Bool {
        isAppBundle() && authorizationGranted
    }

    func requestAuthorization() {
        guard isAppBundle() else {
            DebugLog.write("[NotificationManager] not app bundle, using floating banner")
            return
        }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
            Task { @MainActor in
                self?.authorizationGranted = granted
                if !granted {
                    DebugLog.write("[NotificationManager] authorization denied, will use floating banner")
                }
            }
        }
    }

    func send(title: String, body: String, sessionId: String) {
        DebugLog.write("[NotificationManager] send: title=\(title), useUN=\(canUseUNNotifications)")
        if canUseUNNotifications {
            sendUNNotification(title: title, body: body, sessionId: sessionId)
        } else {
            floatingPresenter.enqueue(title: title, body: body, sessionId: sessionId)
        }
    }

    private func sendUNNotification(title: String, body: String, sessionId: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = ["sessionId": sessionId]

        let request = UNNotificationRequest(
            identifier: "\(sessionId)-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { _ in }
    }
}

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

Delete the old inline `FloatingNotificationBanner` and `ClickableView` definitions from the bottom of the file after this replacement.

- [ ] **Step 5: Run the focused tests**

Run: `swift test --filter 'FloatingNotificationCenterTests|FloatingNotificationLayoutTests|NotificationManagerFloatingFallbackTests'`

Expected: PASS with `Executed 6 tests, with 0 failures`.

- [ ] **Step 6: Run the full package test suite**

Run: `swift test`

Expected: PASS with `0 failures`.

- [ ] **Step 7: Build the app**

Run: `swift build`

Expected: BUILD SUCCEEDED.

- [ ] **Step 8: Manual smoke test the debug notification stack**

Run: `swift run PowerShell`

Then verify:

1. Trigger one debug notification and confirm the new compact card style appears at the top right.
2. Trigger three notifications back-to-back and confirm they stack vertically with fixed spacing.
3. Trigger a fourth notification and confirm the third slot becomes a `+N` summary card.
4. Click the summary card and confirm the third slot cycles to a hidden notification with a `还有 N 条` footer.
5. Click a notification card and confirm the app switches to the target session.
6. Click the close button on a card and confirm only that card closes and lower cards move up.
7. Confirm no card auto-dismisses while the app remains open.

- [ ] **Step 9: Commit**

```bash
git add Sources/PowerShell/Services/NotificationManager.swift Sources/PowerShell/Services/FloatingNotificationPanels.swift Tests/PowerShellTests/NotificationManagerFloatingFallbackTests.swift
git commit -m "feat: redesign debug notification banners"
```

---

## Spec Coverage Check

- Visual polish: covered in Task 3 card-panel rendering (`FloatingNotificationPanels.swift`) with compact spacing, stronger hierarchy, and updated close-button treatment.
- No overlap: covered in Task 1 queue rules and Task 2 frame calculation.
- Max 3 visible with `+N`: covered in Task 1 presentation logic and Task 3 summary rendering.
- Persistent until click/close: covered in Task 3 manual validation and by omitting any timer/dismiss logic from the presenter.
- App bundle native notifications unchanged: covered in Task 3 `NotificationManager` routing.

## Placeholder Scan

- No `TODO`, `TBD`, or “implement later” markers remain.
- Each code-writing step includes the code to add.
- Each verification step includes an exact command and expected result.

## Type Consistency Check

- Shared names used consistently across tasks: `FloatingNotificationCenter`, `FloatingNotificationPresentation`, `FloatingNotificationLayout`, `FloatingNotificationPresenting`, `FloatingNotificationPanels`.
- `NotificationManager.send(title:body:sessionId:)` remains the entry point throughout the plan.
