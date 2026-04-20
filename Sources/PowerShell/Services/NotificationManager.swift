import AppKit
import Foundation
import UserNotifications

protocol UserNotificationCenterProviding: AnyObject {
    var delegate: UNUserNotificationCenterDelegate? { get set }

    func requestAuthorization(
        options: UNAuthorizationOptions,
        completionHandler: @escaping (Bool, Error?) -> Void
    )

    func add(_ request: UNNotificationRequest, withCompletionHandler completionHandler: ((Error?) -> Void)?)
}

extension UNUserNotificationCenter: UserNotificationCenterProviding {}

@MainActor
final class NotificationManager: NSObject {
    static let shared = NotificationManager()

    var onNotificationClicked: ((String) -> Void)?

    private var authorizationGranted = false
    private let notificationCenter: UserNotificationCenterProviding
    private let bundleInspector: () -> Bool
    private let floatingPresenter: FloatingNotificationPresenting

    private var isAppBundle: Bool {
        bundleInspector()
    }

    private var canUseUNNotifications: Bool {
        isAppBundle && authorizationGranted
    }

    init(
        notificationCenter: UserNotificationCenterProviding = UNUserNotificationCenter.current(),
        bundleInspector: @escaping () -> Bool = { Bundle.main.bundleURL.pathExtension == "app" },
        floatingPresenter: FloatingNotificationPresenting = FloatingNotificationPanelPresenter()
    ) {
        self.notificationCenter = notificationCenter
        self.bundleInspector = bundleInspector
        self.floatingPresenter = floatingPresenter
        super.init()
    }

    func requestAuthorization() {
        guard isAppBundle else {
            DebugLog.write("[NotificationManager] not app bundle, using floating presenter")
            return
        }
        notificationCenter.delegate = self
        notificationCenter.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
            Task { @MainActor in
                self?.authorizationGranted = granted
                if !granted {
                    DebugLog.write("[NotificationManager] authorization denied, will use floating presenter")
                }
            }
        }
    }

    func send(title: String, body: String, sessionId: String) {
        DebugLog.write("[NotificationManager] send: title=\(title), useUN=\(canUseUNNotifications)")
        if canUseUNNotifications {
            sendUNNotification(title: title, body: body, sessionId: sessionId)
        } else {
            floatingPresenter.show(title: title, body: body, sessionId: sessionId)
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
        notificationCenter.add(request) { _ in }
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
