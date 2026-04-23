import XCTest
@testable import PowerShell

@MainActor
final class SessionManagerSplitTests: XCTestCase {

    func test_split_setsSplitPair() {
        let manager = SessionManager()
        let s1 = manager.createSession(name: "A")
        let s2 = manager.createSession(name: "B")

        manager.split(primary: s1.id, secondary: s2.id)

        XCTAssertEqual(manager.splitPair?.primary, s1.id)
        XCTAssertEqual(manager.splitPair?.secondary, s2.id)
        XCTAssertEqual(manager.splitRatio, 0.5)
    }

    func test_unsplit_clearsSplitPair() {
        let manager = SessionManager()
        let s1 = manager.createSession(name: "A")
        let s2 = manager.createSession(name: "B")
        manager.split(primary: s1.id, secondary: s2.id)

        manager.unsplit()

        XCTAssertNil(manager.splitPair)
    }

    func test_delete_primary_callsUnsplit() {
        let manager = SessionManager()
        let s1 = manager.createSession(name: "A")
        let s2 = manager.createSession(name: "B")
        manager.split(primary: s1.id, secondary: s2.id)

        manager.delete(sessionId: s1.id)

        XCTAssertNil(manager.splitPair)
    }

    func test_delete_secondary_callsUnsplit() {
        let manager = SessionManager()
        let s1 = manager.createSession(name: "A")
        let s2 = manager.createSession(name: "B")
        manager.split(primary: s1.id, secondary: s2.id)

        manager.delete(sessionId: s2.id)

        XCTAssertNil(manager.splitPair)
    }

    func test_delete_unrelated_doesNotUnsplit() {
        let manager = SessionManager()
        let s1 = manager.createSession(name: "A")
        let s2 = manager.createSession(name: "B")
        let s3 = manager.createSession(name: "C")
        manager.split(primary: s1.id, secondary: s2.id)

        manager.delete(sessionId: s3.id)

        XCTAssertNotNil(manager.splitPair)
    }

    func test_settingActiveSessionOutsideSplit_callsUnsplit() {
        let manager = SessionManager()
        let s1 = manager.createSession(name: "A")
        let s2 = manager.createSession(name: "B")
        let s3 = manager.createSession(name: "C")
        manager.split(primary: s1.id, secondary: s2.id)

        manager.activeSessionId = s3.id

        XCTAssertNil(manager.splitPair)
        XCTAssertEqual(manager.activeSessionId, s3.id)
    }

    func test_settingActiveSessionInsideSplit_keepsSplit() {
        let manager = SessionManager()
        let s1 = manager.createSession(name: "A")
        let s2 = manager.createSession(name: "B")
        manager.split(primary: s1.id, secondary: s2.id)

        manager.activeSessionId = s2.id

        XCTAssertEqual(manager.splitPair?.primary, s1.id)
        XCTAssertEqual(manager.splitPair?.secondary, s2.id)
        XCTAssertEqual(manager.activeSessionId, s2.id)
    }
}
