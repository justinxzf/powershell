import AppKit
import Foundation
import UserNotifications

@MainActor
final class NotificationManager: NSObject {
    static let shared = NotificationManager()

    var onNotificationClicked: ((String) -> Void)?

    private var canUseUNNotifications: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    private override init() {
        super.init()
    }

    func requestAuthorization() {
        if canUseUNNotifications {
            let center = UNUserNotificationCenter.current()
            center.delegate = self
            center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                if !granted {
                    print("NotificationManager: notification authorization denied")
                }
            }
        }
    }

    func send(title: String, body: String, sessionId: String) {
        if canUseUNNotifications {
            sendUNNotification(title: title, body: body, sessionId: sessionId)
        } else {
            FloatingNotificationBanner.show(title: title, body: body, sessionId: sessionId)
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

// MARK: - Floating Banner (fallback for non-app-bundle runs)

private final class FloatingNotificationBanner: NSPanel {
    static func show(title: String, body: String, sessionId: String) {
        DispatchQueue.main.async {
            let banner = FloatingNotificationBanner(title: title, body: body, sessionId: sessionId)
            banner.makeKeyAndOrderFront(nil)
            banner.slideIn()
        }
    }

    private let sessionId: String

    private init(title: String, body: String, sessionId: String) {
        self.sessionId = sessionId
        // Close button
        let closeButton = NSButton(frame: NSRect(x: 0, y: 0, width: 20, height: 20))
        closeButton.bezelStyle = .inline
        closeButton.isBordered = false
        closeButton.title = ""
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "关闭")
        closeButton.imagePosition = .imageOnly
        closeButton.contentTintColor = .white.withAlphaComponent(0.6)
        closeButton.toolTip = "关闭"
        closeButton.setButtonType(.momentaryChange)
        closeButton.focusRingType = .none

        // Title
        let titleField = NSTextField(labelWithString: title)
        titleField.font = .systemFont(ofSize: 13, weight: .semibold)
        titleField.textColor = .white
        titleField.lineBreakMode = .byTruncatingTail
        titleField.maximumNumberOfLines = 1

        // Body
        let bodyField = NSTextField(labelWithString: body)
        bodyField.font = .systemFont(ofSize: 12)
        bodyField.textColor = .white.withAlphaComponent(0.85)
        bodyField.lineBreakMode = .byTruncatingTail
        bodyField.maximumNumberOfLines = 3
        bodyField.preferredMaxLayoutWidth = 260

        let textStack = NSStackView(views: [titleField, bodyField])
        textStack.orientation = .vertical
        textStack.spacing = 3

        let stack = NSStackView(views: [textStack, closeButton])
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 8)
        stack.alignment = .top

        let contentSize = stack.fittingSize
        let width = min(contentSize.width + 24, 320)
        let height = max(contentSize.height + 20, 60)

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        let clickView = ClickableView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        clickView.wantsLayer = true
        clickView.layer?.backgroundColor = NSColor(white: 0.15, alpha: 0.92).cgColor
        clickView.layer?.cornerRadius = 10
        clickView.onClicked = { [weak self] in
            guard let self else { return }
            NotificationManager.shared.onNotificationClicked?(self.sessionId)
            self.dismiss()
        }

        stack.frame = clickView.bounds
        stack.autoresizingMask = [.width, .height]
        clickView.addSubview(stack)

        closeButton.target = self
        closeButton.action = #selector(dismiss)

        contentView = clickView
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func slideIn() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let panelWidth = frame.width
        let panelHeight = frame.height

        let targetX = screenFrame.maxX - panelWidth - 12
        let targetY = screenFrame.maxY - panelHeight - 12

        setFrameOrigin(NSPoint(x: targetX, y: targetY + 40))
        alphaValue = 0

        let targetFrame = NSRect(x: targetX, y: targetY, width: panelWidth, height: panelHeight)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().setFrame(targetFrame, display: true)
            self.animator().alphaValue = 1
        }
    }

    @objc private func dismiss() {
        let origin = frame.origin
        let targetFrame = NSRect(
            x: origin.x,
            y: origin.y + 30,
            width: frame.width,
            height: frame.height
        )

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            self.animator().setFrame(targetFrame, display: true)
            self.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            Task { @MainActor in
                self?.close()
            }
        })
    }
}

// MARK: - Clickable background view

private final class ClickableView: NSView {
    var onClicked: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        onClicked?()
    }
}
