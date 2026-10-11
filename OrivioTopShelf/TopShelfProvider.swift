import TVServices

/// The Dock always presents the supplied n, independent of shared-container
/// entitlements, viewing history and remote images. No account data is needed.
final class TopShelfProvider: TVTopShelfContentProvider {
    override func loadTopShelfContent(completionHandler: @escaping (TVTopShelfContent?) -> Void) {
        guard let image = Bundle.main.url(forResource: "topshelf-full", withExtension: "png") else {
            completionHandler(nil); return
        }
        completionHandler(Self.brandedContent(image: image, identifier: Bundle.main.bundleIdentifier))
    }

    static func brandedContent(image: URL, identifier: String?) -> TVTopShelfCarouselContent {
        let item = TVTopShelfCarouselItem(identifier: "ntv.brand.fullscreen.v2")
        item.title = "nTV"
        // These are alternative device scales, not one combined trait.
        // Register both separately so an exact 1x/2x lookup finds the image.
        item.setImageURL(image, for: .screenScale1x)
        item.setImageURL(image, for: .screenScale2x)
        // The main app's callback scheme follows its signed bundle identity.
        if let identifier, identifier.hasSuffix(".topshelf"),
           let url = URL(string: String(identifier.dropLast(".topshelf".count)) + "://home") {
            item.displayAction = TVTopShelfAction(url: url)
        }
        return TVTopShelfCarouselContent(style: .actions, items: [item])
    }
}
