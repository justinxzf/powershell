import XCTest
import SwiftUI
@testable import PowerShell

final class PowerShellAppTitleBarTests: XCTestCase {
    @MainActor
    func testAppChromeConfigurationUsesRequiredToolbarTitleSeam() {
        let chrome = WindowChromeConfiguration.app

        XCTAssertNil(chrome.navigationTitle)
        XCTAssertEqual(chrome.toolbarTitle, "PowerShell")
        XCTAssertNotNil(ToolbarItem<Void, EmptyView>(placement: chrome.titlePlacement) { EmptyView() })
    }

    @MainActor
    func testFullScreenConfiguratorAppliesRuntimeToolbarPersistenceChange() {
        let window = NSWindow()
        let toolbar = NSToolbar(identifier: "test-toolbar")
        window.toolbar = toolbar
        window.toolbarStyle = .expanded

        let configurator = FullScreenToolbarConfigurator()
        configurator.apply(to: window)

        XCTAssertEqual(window.toolbarStyle, .unified)
        XCTAssertFalse(toolbar.showsBaselineSeparator)
        XCTAssertTrue(window.delegate === configurator)
    }

    @MainActor
    func testFullScreenConfiguratorReusesExistingWindowBinding() {
        let window = NSWindow()
        let toolbar = NSToolbar(identifier: "test-toolbar")
        window.toolbar = toolbar

        let configurator = FullScreenToolbarConfigurator()
        configurator.apply(to: window)
        let firstDelegate = window.delegate

        toolbar.showsBaselineSeparator = true
        window.toolbarStyle = .expanded
        configurator.apply(to: window)

        XCTAssertTrue(window.delegate === firstDelegate)
        XCTAssertEqual(window.toolbarStyle, .unified)
        XCTAssertFalse(toolbar.showsBaselineSeparator)
    }
}
