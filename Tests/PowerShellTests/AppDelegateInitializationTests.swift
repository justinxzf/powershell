import XCTest
import AppKit
@testable import PowerShell

final class AppDelegateInitializationTests: XCTestCase {
    @MainActor
    func testAppDelegateSupportsNSObjectInitializerContract() {
        let delegateType: NSObject.Type = AppDelegate.self

        XCTAssertNoThrow(_ = delegateType.init())
    }
}
