import XCTest
@testable import PowerShell

final class FloatingBubbleChatMessageTests: XCTestCase {
    func testMessageInitialization() {
        let msg = ChatMessage(content: "Hello", isUser: true)
        XCTAssertEqual(msg.content, "Hello")
        XCTAssertTrue(msg.isUser)
        XCTAssertNotNil(msg.id)
        XCTAssertNotNil(msg.timestamp)
    }

    func testMessagesHaveUniqueIds() {
        let msg1 = ChatMessage(content: "A", isUser: true)
        let msg2 = ChatMessage(content: "B", isUser: false)
        XCTAssertNotEqual(msg1.id, msg2.id)
    }
}
