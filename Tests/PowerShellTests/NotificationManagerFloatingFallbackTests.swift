import XCTest
import UserNotifications
@testable import PowerShell

@MainActor
final class NotificationManagerFloatingFallbackTests: XCTestCase {
    func testSendUsesFloatingPresenterWhenNotRunningAsAppBundle() {
        let presenter = RecordingFloatingNotificationPresenter()
        let manager = NotificationManager(
            notificationCenter: StubUserNotificationCenter(),
            bundleInspector: { false },
            floatingPresenter: presenter
        )

        manager.send(title: "PowerShell", body: "body", sessionId: "session-1")

        XCTAssertEqual(
            presenter.messages,
            [
                .init(title: "PowerShell", body: "body", sessionId: "session-1")
            ]
        )
    }
}

@MainActor
private final class RecordingFloatingNotificationPresenter: FloatingNotificationPresenting {
    struct Message: Equatable {
        let title: String
        let body: String
        let sessionId: String
    }

    private(set) var messages: [Message] = []

    func show(title: String, body: String, sessionId: String) {
        messages.append(.init(title: title, body: body, sessionId: sessionId))
    }
}

private final class StubUserNotificationCenter: UserNotificationCenterProviding {
    weak var delegate: UNUserNotificationCenterDelegate?

    func requestAuthorization(
        options: UNAuthorizationOptions,
        completionHandler: @escaping (Bool, (any Error)?) -> Void
    ) {
        completionHandler(false, nil)
    }

    func add(_ request: UNNotificationRequest, withCompletionHandler completionHandler: (((any Error)?) -> Void)?) {
        completionHandler?(nil)
    }
}
