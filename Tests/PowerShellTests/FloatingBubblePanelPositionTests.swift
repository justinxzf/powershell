import XCTest
@testable import PowerShell

@MainActor
final class FloatingBubblePanelPositionTests: XCTestCase {
    func testDefaultPositionIsBottomRightOfScreen() {
        let screenFrame = NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let pos = BubblePositionCalculator.defaultPosition(screenVisibleFrame: screenFrame, bubbleSize: 48)
        XCTAssertEqual(pos.x, 1920 - 60 - 48)
        XCTAssertEqual(pos.y, 60)
    }

    func testClampKeepsBubbleOnScreen() {
        let screenFrame = NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let offscreen = NSPoint(x: 2000, y: -50)
        let clamped = BubblePositionCalculator.clamp(point: offscreen, screenVisibleFrame: screenFrame, bubbleSize: 48)
        XCTAssertLessThanOrEqual(clamped.x + 48, screenFrame.maxX)
        XCTAssertGreaterThanOrEqual(clamped.x, screenFrame.minX)
        XCTAssertLessThanOrEqual(clamped.y + 48, screenFrame.maxY)
        XCTAssertGreaterThanOrEqual(clamped.y, screenFrame.minY)
    }

    func testChatPanelAnchorDefaultsToLeft() {
        let bubbleFrame = NSRect(x: 500, y: 300, width: 48, height: 48)
        let screenFrame = NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let anchor = BubblePositionCalculator.chatPanelOrigin(
            bubbleFrame: bubbleFrame,
            chatSize: NSSize(width: 320, height: 420),
            screenVisibleFrame: screenFrame
        )
        XCTAssertLessThan(anchor.x, bubbleFrame.minX)
    }

    func testChatPanelFlipsToRightWhenNoSpaceOnLeft() {
        let bubbleFrame = NSRect(x: 50, y: 300, width: 48, height: 48)
        let screenFrame = NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let anchor = BubblePositionCalculator.chatPanelOrigin(
            bubbleFrame: bubbleFrame,
            chatSize: NSSize(width: 320, height: 420),
            screenVisibleFrame: screenFrame
        )
        XCTAssertGreaterThan(anchor.x, bubbleFrame.maxX)
    }
}
