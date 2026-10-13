import TVServices

/// The Dock always presents the supplied n, independent of shared-container
/// entitlements, viewing history and remote images. No account data is needed.
final class TopShelfProvider: TVTopShelfContentProvider {
    override func loadTopShelfContent(completionHandler: @escaping (TVTopShelfContent?) -> Void) {
        guard let image = Bundle.main.url(forResource: "topshelf-full", withExtension: "png") else {
            completionHandler(nil); return
        }
        let extensionURL = Bundle.main.bundleURL
        let parentURL = extensionURL.deletingLastPathComponent().deletingLastPathComponent()
        let parentInfo = extensionURL.pathExtension == "appex" && parentURL.pathExtension == "app"
            ? Bundle(url: parentURL)?.infoDictionary : nil
        completionHandler(Self.brandedContent(image: image, containingAppInfo: parentInfo))
    }

    static func brandedContent(image: URL, containingAppInfo: [String: Any]?) -> TVTopShelfCarouselContent {
        let item = TVTopShelfCarouselItem(identifier: "ntv.brand.fullscreen.v2")
        item.title = "nTV"
        // These are alternative device scales, not one combined trait.
        // Register both separately so an exact 1x/2x lookup finds the image.
        item.setImageURL(image, for: .screenScale1x)
        item.setImageURL(image, for: .screenScale2x)
        // A signer can rewrite bundle IDs without rewriting CFBundleURLTypes.
        // Use the callback actually registered by the containing application.
        if let types = containingAppInfo?["CFBundleURLTypes"] as? [[String: Any]],
           let callback = types.first(where: { $0["CFBundleURLName"] as? String == "tv.orivio.callback" }),
           let scheme = (callback["CFBundleURLSchemes"] as? [String])?.first,
           scheme.range(of: "^[A-Za-z][A-Za-z0-9+.-]*$", options: .regularExpression) != nil,
           let url = URL(string: scheme + "://home") {
            item.displayAction = TVTopShelfAction(url: url)
        }
        return TVTopShelfCarouselContent(style: .actions, items: [item])
    }
}
