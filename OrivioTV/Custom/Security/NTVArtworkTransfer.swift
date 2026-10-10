import Foundation

/// Artwork budgets apply to encoded bytes too, before ImageIO sees them.
/// The same policy covers fresh HTTP bodies and files left by older builds.
enum NTVArtworkTransfer {
    static let maximumBytes = 16 << 20

    static func configuration() -> URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.httpMaximumConnectionsPerHost = PerformanceProfile.artworkDownloads
        config.timeoutIntervalForRequest = 25
        config.timeoutIntervalForResource = 45
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.urlCredentialStorage = nil
        return config
    }

    static func permits(_ url: URL) -> Bool {
        ["http", "https"].contains(url.scheme?.lowercased() ?? "") &&
            url.host != nil && url.user == nil && url.password == nil &&
            url.absoluteString.utf8.count <= 16_384
    }

    static func data(from url: URL, session: URLSession) async throws -> Data {
        guard permits(url) else { throw URLError(.unsupportedURL) }
        var request = URLRequest(url: url)
        request.setValue("image/*, */*;q=0.5", forHTTPHeaderField: "Accept")
        let (data, response) = try await NTVBoundedResponse.data(
            for: request, session: session, maximumBytes: maximumBytes)
        guard (200..<300).contains(response.statusCode) else { throw URLError(.badServerResponse) }
        return data
    }

    /// Read a bounded amount, including when a file grows after the size check.
    /// Runs inside a detached Swift task so cancellation is checked per chunk.
    static func fileData(from url: URL) throws -> Data {
        try Task.checkCancellation()
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        guard try file.seekToEnd() <= UInt64(maximumBytes) else { throw NTVBoundedResponse.Failure.tooLarge }
        try file.seek(toOffset: 0)
        var data = Data()
        while true {
            try Task.checkCancellation()
            let chunk = try file.read(upToCount: min(64 << 10, maximumBytes - data.count + 1)) ?? Data()
            if chunk.isEmpty { return data }
            guard chunk.count <= maximumBytes - data.count else { throw NTVBoundedResponse.Failure.tooLarge }
            data.append(chunk)
        }
    }
}
