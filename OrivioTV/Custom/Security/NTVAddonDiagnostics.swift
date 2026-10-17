import Foundation

/// Diagnostic categories only: a manifest path, host or NSError description
/// can carry credentials. Neither malformed inputs nor errors are echoed.
enum NTVAddonDiagnostics {
    static func requestName(_ raw: String) -> String {
        guard let url = URL(string: raw), ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.host != nil else { return "addon-url-invalid" }
        if url.lastPathComponent == "manifest.json" { return "addon-manifest" }
        for resource in ["catalog", "meta", "stream", "subtitles"] {
            if url.path.contains("/" + resource + "/") { return "addon-" + resource }
        }
        return "addon-request"
    }

    static func failure(_ error: Error) -> String {
        if error is CancellationError { return "cancelled" }
        if let error = error as? StremioAPIError {
            switch error {
            case .badURL: return "invalid-url"
            case .badResponse(let status): return "http-" + String(status)
            case .emptyBody: return "empty-body"
            case .responseTooLarge: return "body-too-large"
            case .invalidResponse: return "invalid-response"
            }
        }
        if error is DecodingError { return "invalid-json" }
        if let error = error as? URLError { return "network-" + String(error.code.rawValue) }
        return "request-failed"
    }
}
