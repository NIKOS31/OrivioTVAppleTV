import Foundation

/// Policy for addon JSON requests only. Native media, artwork, subtitles and
/// explicitly configured LAN services require their own destination policy.
enum NTVAddonTransportPolicy {
    static func target(_ raw: String) throws -> URL {
        guard raw.utf8.count <= 16_384,
              !raw.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }),
              let url = URL(string: raw), permits(url) else {
            // Keep configured paths and queries out of thrown diagnostics.
            throw StremioAPIError.badURL("addon")
        }
        return url
    }

    static func permits(_ url: URL) -> Bool {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil else { return false }
        if let port = url.port, !(1...65_535).contains(port) { return false }
        return true
    }

    static func permitsRedirect(from original: URL, to destination: URL, current: URL? = nil) -> Bool {
        let previous = current ?? original
        if publicCinemetaCatalogAlias(from: original, to: destination, current: previous) { return true }
        guard permits(original), permits(previous), permits(destination),
              original.host?.lowercased() == previous.host?.lowercased(),
              original.host?.lowercased() == destination.host?.lowercased() else { return false }
        let sourceScheme = original.scheme!.lowercased()
        let targetScheme = destination.scheme!.lowercased()
        // Check every hop, including a downgrade after an initial HTTP upgrade.
        if previous.scheme?.lowercased() == "https", targetScheme != "https" { return false }
        let sourcePort = original.port ?? (sourceScheme == "https" ? 443 : 80)
        let targetPort = destination.port ?? (targetScheme == "https" ? 443 : 80)
        if sourceScheme == targetScheme { return sourcePort == targetPort }
        // A conventional same-host HTTP upgrade is allowed; HTTPS downgrade,
        // another host or another service port cannot receive the request.
        return sourceScheme == "http" && sourcePort == 80
            && targetScheme == "https" && targetPort == 443
    }

    /// The built-in, unconfigured Cinemeta catalogs redirect to this separate
    /// publisher endpoint. No configured path/query or arbitrary addon host
    /// can use the exception, and the original public resource path is kept.
    private static func publicCinemetaCatalogAlias(from original: URL, to destination: URL, current: URL) -> Bool {
        let urls = [original, destination, current]
        guard urls.allSatisfy({ permits($0) && $0.scheme?.lowercased() == "https"
            && ($0.port ?? 443) == 443 && $0.query == nil && $0.fragment == nil }),
              original.host?.lowercased() == "v3-cinemeta.strem.io",
              current.host?.lowercased() == original.host?.lowercased(),
              destination.host?.lowercased() == "cinemeta-catalogs.strem.io",
              let path = URLComponents(url: original, resolvingAgainstBaseURL: false)?.percentEncodedPath,
              URLComponents(url: current, resolvingAgainstBaseURL: false)?.percentEncodedPath == path,
              let targetPath = URLComponents(url: destination, resolvingAgainstBaseURL: false)?.percentEncodedPath else { return false }
        let parts = path.split(separator: "/").map(String.init)
        guard (3...4).contains(parts.count), parts[0] == "catalog",
              ["movie", "series"].contains(parts[1]), parts.last?.hasSuffix(".json") == true else { return false }
        let id = parts.count == 3 ? String(parts[2].dropLast(5)) : parts[2]
        guard ["top", "year", "imdbRating", "last-videos", "calendar-videos"].contains(id) else { return false }
        if targetPath == "/" + id + path { return true }
        return parts.count == 4 && parts[3].hasPrefix("search=") && targetPath == "/search" + path
    }

    static func makeSession(configuration: URLSessionConfiguration) -> URLSession {
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration, delegate: RedirectGuard(), delegateQueue: nil)
    }

    private final class RedirectGuard: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest,
                        completionHandler: @escaping (URLRequest?) -> Void) {
            guard let original = task.originalRequest?.url, let target = request.url,
                  permitsRedirect(from: original, to: target, current: response.url) else {
                completionHandler(nil); return
            }
            var safe = request
            for header in ["Authorization", "Proxy-Authorization", "Cookie", "Cookie2"] {
                safe.setValue(nil, forHTTPHeaderField: header)
            }
            completionHandler(safe)
        }
    }
}
