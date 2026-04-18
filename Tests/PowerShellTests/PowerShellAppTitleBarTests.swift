import XCTest
import SwiftUI
@testable import PowerShell

final class PowerShellAppTitleBarTests: XCTestCase {
    @MainActor
    func testWindowChromeConfigurationUsesExpectedFixedValues() {
        XCTAssertNil(WindowChromeConfiguration.navigationTitle)
        XCTAssertEqual(WindowChromeConfiguration.toolbarTitle, "PowerShell")
        XCTAssertEqual(
            String(describing: WindowChromeConfiguration.titlePlacement),
            String(describing: ToolbarItemPlacement.principal)
        )
    }
}
