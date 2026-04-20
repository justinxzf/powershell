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
