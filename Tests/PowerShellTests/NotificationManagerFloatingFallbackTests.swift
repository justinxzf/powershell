import AppKit
import XCTest
@testable import PowerShell

@MainActor
final class NotificationManagerFloatingFallbackTests: XCTestCase {
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

    func testDefaultInitializerSupportsFloatingOnlyNotificationManager() {
        XCTAssertNoThrow(
            _ = NotificationManager(
                floatingPresenter: RecordingFloatingNotificationPresenter()
            )
        )
    }

    func testOpeningCardDismissesSessionAndInvokesSelectionHandler() {
        let center = FloatingNotificationCenter()
        center.enqueue(title: "PowerShell", body: "body", sessionId: "session-1")

        let presenter = FloatingNotificationPanelPresenter(center: center)
        var openedSessionId: String?
        presenter.onOpenSession = { openedSessionId = $0 }

        presenter.handleTestingAction(.open(sessionId: "session-1"))

        XCTAssertEqual(openedSessionId, "session-1")
        XCTAssertTrue(center.presentations().isEmpty)
    }

    func testClosingCardDismissesSessionWithoutInvokingSelectionHandler() {
        let center = FloatingNotificationCenter()
        center.enqueue(title: "PowerShell", body: "body", sessionId: "session-1")

        let presenter = FloatingNotificationPanelPresenter(center: center)
        var openedSessionId: String?
        presenter.onOpenSession = { openedSessionId = $0 }

        presenter.handleTestingAction(.close(sessionId: "session-1"))

        XCTAssertNil(openedSessionId)
        XCTAssertTrue(center.presentations().isEmpty)
    }

    func testNotificationManagerWiresPresenterOpenCallbackToNotificationHandler() {
        let presenter = RecordingInteractiveFloatingPresenter()
        let manager = NotificationManager(floatingPresenter: presenter)

        var openedSessionId: String?
        manager.onNotificationClicked = { openedSessionId = $0 }

        presenter.triggerOpen(sessionId: "session-9")

        XCTAssertEqual(openedSessionId, "session-9")
    }

    func testClickResolverReturnsNilForCloseButtonHit() {
        let action = FloatingNotificationClickResolver.action(
            sessionId: "session-1",
            clickLocation: NSPoint(x: 8, y: 8),
            closeButtonFrame: NSRect(x: 0, y: 0, width: 16, height: 16)
        )

        XCTAssertNil(action)
    }

    func testClickResolverReturnsOpenActionForCardBodyHit() {
        let action = FloatingNotificationClickResolver.action(
            sessionId: "session-1",
            clickLocation: NSPoint(x: 40, y: 20),
            closeButtonFrame: NSRect(x: 0, y: 0, width: 16, height: 16)
        )

        XCTAssertEqual(action, .open(sessionId: "session-1"))
    }

    func testClickResolverReturnsCloseActionForCardBodyHitWhenSessionIdIsEmpty() {
        let action = FloatingNotificationClickResolver.action(
            sessionId: "",
            clickLocation: NSPoint(x: 40, y: 20),
            closeButtonFrame: NSRect(x: 0, y: 0, width: 16, height: 16)
        )

        XCTAssertEqual(action, .close(sessionId: ""))
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

@MainActor
private final class RecordingInteractiveFloatingPresenter: FloatingNotificationPresenting, FloatingNotificationSessionOpening {
    var onOpenSession: ((String) -> Void)?

    func show(title: String, body: String, sessionId: String) {}

    func triggerOpen(sessionId: String) {
        onOpenSession?(sessionId)
    }
}
