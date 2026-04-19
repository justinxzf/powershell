import XCTest
import AppKit
@testable import PowerShell

@MainActor
final class AppIconProviderBehaviorTests: XCTestCase {
    func testLoadImageReturnsNilAndDoesNotApplyWhenResourceIsMissing() {
        let application = AppIconApplyingSpy()
        var resolvedName: String?
        var resolvedExtension: String?
        var didAttemptLoad = false

        let provider = AppIconProvider(
            resourceURL: { name, ext in
                resolvedName = name
                resolvedExtension = ext
                return nil
            },
            imageLoader: { _ in
                didAttemptLoad = true
                return nil
            },
            application: application
        )

        let image = provider.loadImage()
        provider.applyAppIcon()

        XCTAssertNil(image)
        XCTAssertEqual(resolvedName, "AppIcon")
        XCTAssertEqual(resolvedExtension, "icns")
        XCTAssertFalse(didAttemptLoad)
        XCTAssertTrue(application.appliedImages.isEmpty)
    }

    func testApplyAppIconLoadsAndAppliesImageWhenResourceExists() {
        let expectedURL = URL(fileURLWithPath: "/tmp/AppIcon.icns")
        let expectedImage = NSImage(size: NSSize(width: 32, height: 32))
        let application = AppIconApplyingSpy()
        var loaderReceivedURL: URL?

        let provider = AppIconProvider(
            resourceURL: { name, ext in
                XCTAssertEqual(name, "AppIcon")
                XCTAssertEqual(ext, "icns")
                return expectedURL
            },
            imageLoader: { url in
                loaderReceivedURL = url
                return expectedImage
            },
            application: application
        )

        let image = provider.loadImage()
        provider.applyAppIcon()

        XCTAssertTrue(image === expectedImage)
        XCTAssertEqual(image?.size, NSSize(width: 512, height: 512))
        XCTAssertEqual(loaderReceivedURL, expectedURL)
        XCTAssertEqual(application.appliedImages.count, 1)
        XCTAssertTrue(application.appliedImages.first === expectedImage)
    }
}

@MainActor
private final class AppIconApplyingSpy: AppIconApplying {
    private(set) var appliedImages: [NSImage] = []

    func applyApplicationIcon(_ image: NSImage) {
        appliedImages.append(image)
    }
}
