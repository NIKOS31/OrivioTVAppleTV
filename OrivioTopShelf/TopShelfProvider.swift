import TVServices

/// The Dock always presents the supplied n, independent of shared-container
/// entitlements, viewing history and remote images. No account data is needed.
final class TopShelfProvider: TVTopShelfContentProvider {
    override func loadTopShelfContent(completionHandler: @escaping (TVTopShelfContent?) -> Void) {
        guard let image = Bundle.main.url(forResource: "topshelf-full", withExtension: "png") else {
            completionHandler(nil); return
        }
        let item = TVTopShelfCarouselItem(identifier: "ntv.brand.fullscreen.v1")
        item.title = "nTV"
        item.setImageURL(image, for: [.screenScale1x, .screenScale2x])
        // The main app's callback scheme follows its signed bundle identity.
        if let identifier = Bundle.main.bundleIdentifier, identifier.hasSuffix(".topshelf"),
           let url = URL(string: String(identifier.dropLast(".topshelf".count)) + "://home") {
            item.displayAction = TVTopShelfAction(url: url)
        }
        completionHandler(TVTopShelfCarouselContent(style: .actions, items: [item]))
    }
}
