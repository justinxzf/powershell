import AppKit

struct AppIconConfiguration: Equatable {
    let resourceName: String
    let fileExtension: String
    let expectedSize: NSSize

    static let `default` = AppIconConfiguration(
        resourceName: "AppIcon",
        fileExtension: "icns",
        expectedSize: NSSize(width: 512, height: 512)
    )
}

@MainActor
protocol AppIconApplying: AnyObject {
    func applyApplicationIcon(_ image: NSImage)
}

@MainActor
protocol AppIconProviding {
    func loadImage() -> NSImage?
    func applyAppIcon()
}

@MainActor
final class AppIconProvider: AppIconProviding {
    typealias ResourceURLResolver = (String, String) -> URL?
    typealias ImageLoader = (URL) -> NSImage?

    private let configuration: AppIconConfiguration
    private let resourceURL: ResourceURLResolver
    private let imageLoader: ImageLoader
    private let application: AppIconApplying

    init(
        configuration: AppIconConfiguration = .default,
        bundle: Bundle = Bundle.main,
        imageLoader: @escaping ImageLoader = { url in
            NSImage(contentsOf: url)
        },
        application: AppIconApplying = NSApplication.shared
    ) {
        self.configuration = configuration
        self.resourceURL = { name, ext in
            bundle.url(forResource: name, withExtension: ext)
        }
        self.imageLoader = imageLoader
        self.application = application
    }

    init(
        configuration: AppIconConfiguration = .default,
        resourceURL: @escaping ResourceURLResolver,
        imageLoader: @escaping ImageLoader,
        application: AppIconApplying
    ) {
        self.configuration = configuration
        self.resourceURL = resourceURL
        self.imageLoader = imageLoader
        self.application = application
    }

    func loadImage() -> NSImage? {
        guard let imageURL = resourceURL(
            configuration.resourceName,
            configuration.fileExtension
        ), let image = imageLoader(imageURL) else {
            return nil
        }

        image.size = configuration.expectedSize
        return image
    }

    func applyAppIcon() {
        guard let image = loadImage() else { return }
        application.applyApplicationIcon(image)
    }
}

extension NSApplication: AppIconApplying {
    func applyApplicationIcon(_ image: NSImage) {
        applicationIconImage = image
    }
}
