import AppKit
import XCTest
@testable import PowerShell

final class FloatingNotificationLayoutTests: XCTestCase {
    func testFramesStackFromTopRightWithFixedSpacing() {
        let layout = FloatingNotificationLayout(
            cardWidth: 320,
            cardHeight: 92,
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

    func testCardsContinueStackingBeyondThreeItems() {
        let layout = FloatingNotificationLayout(
            cardWidth: 320,
            cardHeight: 92,
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

    func testCardWithFooterUsesTallerHeightToAvoidContentOverlap() {
        let layout = FloatingNotificationLayout(
            cardWidth: 320,
            cardHeight: 92,
            topInset: 12,
            rightInset: 12,
            spacing: 10
        )

        let frames = layout.frames(
            for: [
                .card(title: "one", body: "body-1", sessionId: "s1", footer: "还有 2 条"),
                .card(title: "two", body: "body-2", sessionId: "s2", footer: nil)
            ],
            visibleFrame: NSRect(x: 0, y: 0, width: 1440, height: 900)
        )

        XCTAssertEqual(frames[0].height, 110)
        XCTAssertEqual(frames[0].minY - frames[1].maxY, 10)
        XCTAssertEqual(frames[1].height, 92)
    }
}
