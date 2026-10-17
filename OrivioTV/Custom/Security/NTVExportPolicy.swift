import Foundation

/// A plain backup is for library state, never reusable provider access.
/// Unknown configured URLs are private by default, even without a token query.
enum NTVExportPolicy {
    static func permitsPublicManifest(_ value: String) -> Bool {
        ["https://v3-cinemeta.strem.io/manifest.json",
         "https://opensubtitles-v3.strem.io/manifest.json"].contains(value)
    }

    static func sanitizedJSON(_ data: Data) throws -> Data {
        let json = try JSONSerialization.jsonObject(with: data)
        return try JSONSerialization.data(withJSONObject: clean(json), options: [.prettyPrinted, .sortedKeys])
    }

    private static func clean(_ value: Any) -> Any {
        if let object = value as? [String: Any] {
            return object.reduce(into: [String: Any]()) { result, entry in
                let normalized = entry.key.lowercased().filter { $0.isLetter || $0.isNumber }
                let privateFields = ["authorization", "cookie", "apikey", "accesstoken", "refreshtoken",
                                     "password", "secret", "credential", "proxyheaders"]
                if privateFields.contains(where: { normalized.contains($0) }) { return }
                result[entry.key] = clean(entry.value)
            }
        }
        if let array = value as? [Any] { return array.map(clean) }
        if let string = value as? String,
           string.range(of: "(?:https?://|stremio://|magnet:)", options: [.regularExpression, .caseInsensitive]) != nil {
            return permitsPublicManifest(string) ? string : ""
        }
        return value
    }
}
