import AppKit
import Foundation

@MainActor
final class NotificationManager: NSObject {
    static let shared = NotificationManager()

    var onNotificationClicked: ((String) -> Void)?

    private let floatingPresenter: FloatingNotificationPresenting

    init(
        floatingPresenter: FloatingNotificationPresenting = FloatingNotificationPanelPresenter()
    ) {
        self.floatingPresenter = floatingPresenter
        super.init()
        configureFloatingPresenterCallbacks()
    }

    func send(title: String, body: String, sessionId: String) {
        DebugLog.write("[NotificationManager] send: title=\(title), using floating presenter")
        floatingPresenter.show(title: title, body: body, sessionId: sessionId)
    }

    private func configureFloatingPresenterCallbacks() {
        guard let floatingPresenter = floatingPresenter as? FloatingNotificationSessionOpening else {
            return
        }

        floatingPresenter.onOpenSession = { [weak self] sessionId in
            self?.onNotificationClicked?(sessionId)
        }
    }
}
