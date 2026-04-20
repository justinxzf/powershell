import AppKit
import XCTest
@testable import PowerShell

final class FloatingNotificationLayoutTests: XCTestCase {
    func testFramesStackFromTopRightWithFixedSpacingAndSummaryHeight() {
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
                .card(title: "one", body: "body-1", sessionId: "s1", footer: nil),
                .card(title: "two", body: "body-2", sessionId: "s2", footer: nil),
                .summary(hiddenCount: 2)
            ],
            visibleFrame: NSRect(x: 0, y: 0, width: 1440, height: 900)
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

    func testThirdCardUsesCardHeightWhilePreservingFixedSpacing() {
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
                .card(title: "one", body: "body-1", sessionId: "s1", footer: nil),
                .card(title: "two", body: "body-2", sessionId: "s2", footer: nil),
                .card(title: "three", body: "body-3", sessionId: "s3", footer: nil)
            ],
            visibleFrame: NSRect(x: 0, y: 0, width: 1440, height: 900)
        )

        XCTAssertEqual(
            frames[2],
            NSRect(x: 1108, y: 592, width: 320, height: 92)
        )
    }
}
