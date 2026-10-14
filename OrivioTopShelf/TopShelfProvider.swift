import TVServices
#if NTV_TOPSHELF_TEST_HOST
@testable import OrivioTV
#endif

/// The Dock offers the active unlocked profile's locally exported continuation
/// list. Without authorized local sharing, or with no history, branding remains
/// available. The extension never requests stream/addon URLs or account keys.
final class TopShelfProvider: TVTopShelfContentProvider {
    override func loadTopShelfContent(completionHandler: @escaping (TVTopShelfContent?) -> Void) {
        guard let image = Bundle.main.url(forResource: "topshelf-full", withExtension: "png") else {
            completionHandler(nil); return
        }
        let extensionURL = Bundle.main.bundleURL
        let parentURL = extensionURL.deletingLastPathComponent().deletingLastPathComponent()
        let parentInfo = extensionURL.pathExtension == "appex" && parentURL.pathExtension == "app"
            ? Bundle(url: parentURL)?.infoDictionary : nil
        if let file = AppGroupResolver.sharedFile("topshelf.json"),
           let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize,
           size <= NTVTopShelfSnapshot.maximumBytes,
           let data = try? Data(contentsOf: file),
           let snapshot = NTVTopShelfSnapshot.decode(data),
           let content = Self.continuationContent(snapshot, containingAppInfo: parentInfo,
               artworkDirectory: file.deletingLastPathComponent(), fallbackImage: image) {
            completionHandler(content)
        } else {
            completionHandler(Self.brandedContent(image: image, containingAppInfo: parentInfo))
        }
    }

    static func continuationContent(_ snapshot: NTVTopShelfSnapshot,
                                    containingAppInfo: [String: Any]?, artworkDirectory: URL,
                                    fallbackImage: URL) -> TVTopShelfSectionedContent? {
        guard let scheme = callbackScheme(containingAppInfo) else { return nil }
        var seen = Set<String>()
        let items = snapshot.entries.prefix(10).compactMap { entry -> TVTopShelfSectionedItem? in
            guard ["movie", "series"].contains(entry.type), !entry.id.isEmpty,
                  entry.id.utf8.count <= 256, !entry.title.isEmpty, entry.title.utf8.count <= 512,
                  seen.insert(entry.type + "#" + entry.id).inserted else { return nil }
            let item = TVTopShelfSectionedItem(identifier: entry.type + "#" + entry.id)
            item.title = entry.subtitle.map { entry.title + " · " + String($0.prefix(80)) } ?? entry.title
            item.imageShape = .poster
            var artwork = fallbackImage
            if let name = entry.imageFileName, NTVTopShelfSnapshot.safeArtworkName(name) {
                let local = artworkDirectory.appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: local.path) { artwork = local }
            }
            item.setImageURL(artwork, for: .screenScale1x)
            item.setImageURL(artwork, for: .screenScale2x)
            item.playbackProgress = entry.progress.flatMap { $0.isFinite ? min(max($0, 0), 1) : nil } ?? 0
            var display = URLComponents(); display.scheme = scheme; display.host = "meta"
            display.queryItems = [URLQueryItem(name: "type", value: entry.type), URLQueryItem(name: "id", value: entry.id)]
            var play = display; play.host = "resume"
            guard let displayURL = display.url, let playURL = play.url else { return nil }
            item.displayAction = TVTopShelfAction(url: displayURL)
            item.playAction = TVTopShelfAction(url: playURL)
            return item
        }
        guard !items.isEmpty else { return nil }
        let section = TVTopShelfItemCollection(items: items)
        section.title = "Continuer à regarder"
        return TVTopShelfSectionedContent(sections: [section])
    }

    private static func callbackScheme(_ info: [String: Any]?) -> String? {
        guard let types = info?["CFBundleURLTypes"] as? [[String: Any]],
              let callback = types.first(where: { $0["CFBundleURLName"] as? String == "tv.orivio.callback" }),
              let scheme = (callback["CFBundleURLSchemes"] as? [String])?.first,
              scheme.range(of: "^[A-Za-z][A-Za-z0-9+.-]*$", options: .regularExpression) != nil else { return nil }
        return scheme
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
        if let scheme = callbackScheme(containingAppInfo),
           let url = URL(string: scheme + "://home") {
            item.displayAction = TVTopShelfAction(url: url)
        }
        return TVTopShelfCarouselContent(style: .actions, items: [item])
    }
}
