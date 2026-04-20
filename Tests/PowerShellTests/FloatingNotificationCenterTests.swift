import XCTest
@testable import PowerShell

@MainActor
final class FloatingNotificationCenterTests: XCTestCase {
    func testSameSessionAggregatesLatestContentAndFooter() {
        let center = FloatingNotificationCenter()

        center.enqueue(title: "首条标题", body: "首条内容", sessionId: "session-a")
        center.enqueue(title: "更新标题", body: "更新内容", sessionId: "session-a")
        center.enqueue(title: "最终标题", body: "最终内容", sessionId: "session-a")

        XCTAssertEqual(
            center.presentations(),
            [
                .card(title: "最终标题", body: "最终内容", sessionId: "session-a", footer: "还有 2 条")
            ]
        )
    }

    func testFooterIsNilForFirstNotificationAndAppearsFromSecondOnward() {
        let center = FloatingNotificationCenter()

        center.enqueue(title: "首条标题", body: "首条内容", sessionId: "session-a")
        XCTAssertEqual(
            center.presentations(),
            [
                .card(title: "首条标题", body: "首条内容", sessionId: "session-a", footer: nil)
            ]
        )

        center.enqueue(title: "第二条标题", body: "第二条内容", sessionId: "session-a")
        XCTAssertEqual(
            center.presentations(),
            [
                .card(title: "第二条标题", body: "第二条内容", sessionId: "session-a", footer: "还有 1 条")
            ]
        )
    }

    func testUpdatingExistingSessionMovesItToTop() {
        let center = FloatingNotificationCenter()

        center.enqueue(title: "A1", body: "body", sessionId: "session-a")
        center.enqueue(title: "B1", body: "body", sessionId: "session-b")
        center.enqueue(title: "A2", body: "body", sessionId: "session-a")

        XCTAssertEqual(
            center.presentations(),
            [
                .card(title: "A2", body: "body", sessionId: "session-a", footer: "还有 1 条"),
                .card(title: "B1", body: "body", sessionId: "session-b", footer: nil)
            ]
        )
    }

    func testDismissSessionRemovesWholeCard() {
        let center = FloatingNotificationCenter()

        center.enqueue(title: "A1", body: "body", sessionId: "session-a")
        center.enqueue(title: "A2", body: "body", sessionId: "session-a")
        center.enqueue(title: "B1", body: "body", sessionId: "session-b")

        center.dismiss(sessionId: "session-a")

        XCTAssertEqual(
            center.presentations(),
            [
                .card(title: "B1", body: "body", sessionId: "session-b", footer: nil)
            ]
        )
    }

    func testDismissingThenReEnqueueingSameSessionWorks() {
        let center = FloatingNotificationCenter()

        center.enqueue(title: "A1", body: "body", sessionId: "session-a")
        center.enqueue(title: "A2", body: "body", sessionId: "session-a")
        center.dismiss(sessionId: "session-a")

        XCTAssertTrue(center.presentations().isEmpty)

        center.enqueue(title: "A3", body: "fresh", sessionId: "session-a")

        XCTAssertEqual(
            center.presentations(),
            [
                .card(title: "A3", body: "fresh", sessionId: "session-a", footer: nil)
            ]
        )
    }

    func testMultipleSessionsAppearAsCardsWithoutSummaryBehavior() {
        let center = FloatingNotificationCenter()

        center.enqueue(title: "A1", body: "body", sessionId: "session-a")
        center.enqueue(title: "B1", body: "body", sessionId: "session-b")
        center.enqueue(title: "C1", body: "body", sessionId: "session-c")
        center.enqueue(title: "D1", body: "body", sessionId: "session-d")
        center.enqueue(title: "E1", body: "body", sessionId: "session-e")

        XCTAssertEqual(
            center.presentations(),
            [
                .card(title: "E1", body: "body", sessionId: "session-e", footer: nil),
                .card(title: "D1", body: "body", sessionId: "session-d", footer: nil),
                .card(title: "C1", body: "body", sessionId: "session-c", footer: nil),
                .card(title: "B1", body: "body", sessionId: "session-b", footer: nil),
                .card(title: "A1", body: "body", sessionId: "session-a", footer: nil)
            ]
        )
    }
}
