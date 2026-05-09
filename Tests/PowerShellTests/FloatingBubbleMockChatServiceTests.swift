import XCTest
@testable import PowerShell

@MainActor
final class FloatingBubbleMockChatServiceTests: XCTestCase {
    func testReplyReturnsNonEmptyString() async {
        let service = MockChatService()
        let reply = await service.reply(to: "hello")
        XCTAssertFalse(reply.isEmpty)
    }

    func testReplyVariesAcrossCalls() async {
        let service = MockChatService()
        var results = Set<String>()
        for i in 0..<20 {
            let reply = await service.reply(to: "msg \(i)")
            results.insert(reply)
        }
        XCTAssertGreaterThan(results.count, 1, "Expected varied responses")
    }
}
