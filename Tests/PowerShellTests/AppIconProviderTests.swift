import AppKit
import XCTest
@testable import PowerShell

@MainActor
final class AppIconProviderTests: XCTestCase {
    func testDefaultConfigurationUsesAppIconIcnsResource() {
        let configuration = AppIconConfiguration.default

        XCTAssertEqual(configuration.resourceName, "AppIcon")
        XCTAssertEqual(configuration.fileExtension, "icns")
        XCTAssertEqual(configuration.expectedSize, NSSize(width: 512, height: 512))
    }

    func testProviderLoadsBundledIcnsImage() {
        let provider = AppIconProvider()

        let image = provider.loadImage()

        XCTAssertNotNil(image)
        XCTAssertEqual(image?.size, NSSize(width: 512, height: 512))
    }
}
