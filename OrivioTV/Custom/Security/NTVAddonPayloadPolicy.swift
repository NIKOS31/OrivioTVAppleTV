import Foundation

/// Security checks precede the cosmetic/lossy decoders. Bounds apply to raw
/// JSON, so malformed entries cannot evade a collection limit by being skipped.
enum NTVAddonPayloadPolicy {
    enum Resource {
        case manifest, catalog, meta, streams, subtitles

        var maximumBytes: Int {
            switch self {
            case .manifest: return 1 << 20
            case .subtitles: return 2 << 20
            case .streams: return 4 << 20
            case .catalog, .meta: return 8 << 20
            }
        }
    }

    static func checkedData(_ data: Data, resource: Resource, source: URL) throws -> Data {
        guard data.count <= resource.maximumBytes else { throw StremioAPIError.responseTooLarge }
        try preflight(data)
        let decoded: Any
        do { decoded = try JSONSerialization.jsonObject(with: data) }
        catch { throw StremioAPIError.invalidResponse }
        guard var object = decoded as? [String: Any] else {
            throw StremioAPIError.invalidResponse
        }
        var changed = false
        switch resource {
        case .manifest:
            try manifest(object)
            cleanLinks(&object, keys: ["logo"], source: source, changed: &changed)
        case .catalog:
            let entries = try array(object, key: "metas", limit: 1_000)
            var checked: [[String: Any]] = []
            for entry in entries {
                guard var meta = entry as? [String: Any], validMeta(meta) else { changed = true; continue }
                try metaCollections(meta)
                cleanMeta(&meta, source: source, changed: &changed)
                checked.append(meta)
            }
            if changed { object["metas"] = checked }
        case .meta:
            if let value = object["meta"], !(value is NSNull) {
                guard var meta = value as? [String: Any], validMeta(meta) else { throw StremioAPIError.invalidResponse }
                try metaCollections(meta)
                cleanMeta(&meta, source: source, changed: &changed)
                if changed { object["meta"] = meta }
            }
        case .streams:
            let entries = try array(object, key: "streams", limit: 4_096)
            var checked: [[String: Any]] = []
            for entry in entries {
                guard var stream = entry as? [String: Any] else { changed = true; continue }
                cleanLinks(&stream, keys: ["url", "externalUrl"], source: source, changed: &changed)
                cleanHeaders(&stream, changed: &changed)
                if let hash = stream["infoHash"] {
                    if let text = hash as? String, [40, 64].contains(text.utf8.count),
                       text.unicodeScalars.allSatisfy({ (48...57).contains($0.value) || (65...70).contains($0.value) || (97...102).contains($0.value) }) {} else {
                        stream.removeValue(forKey: "infoHash"); changed = true
                    }
                }
                if let values = stream["sources"] as? [Any], values.count > 128 { throw StremioAPIError.responseTooLarge }
                guard stream["url"] is String || stream["externalUrl"] is String || stream["infoHash"] is String else {
                    changed = true; continue
                }
                checked.append(stream)
            }
            if changed { object["streams"] = checked }
        case .subtitles:
            let entries = try array(object, key: "subtitles", limit: 256)
            let checked = entries.compactMap { entry -> [String: Any]? in
                guard let item = entry as? [String: Any], let raw = item["url"] as? String,
                      NTVAddonLinkPolicy.permits(raw, source: source) else { changed = true; return nil }
                return item
            }
            if changed { object["subtitles"] = checked }
        }
        // Preserve normal bodies byte-for-byte; only unsafe optional links or
        // records trigger serialization. Only checked bytes enter the cache.
        return changed ? try JSONSerialization.data(withJSONObject: object) : data
    }

    static func pathComponent(_ text: String) throws -> String {
        guard identifier(text, limit: 512) else { throw StremioAPIError.invalidResponse }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        guard let encoded = text.addingPercentEncoding(withAllowedCharacters: allowed) else {
            throw StremioAPIError.invalidResponse
        }
        return encoded
    }

    private static func preflight(_ data: Data) throws {
        var depth = 0, containers = 0, separators = 0, quoted = false, escaped = false
        for byte in data {
            if quoted {
                if escaped { escaped = false }
                else if byte == 92 { escaped = true }
                else if byte == 34 { quoted = false }
                continue
            }
            if byte == 34 { quoted = true }
            else if byte == 123 || byte == 91 {
                depth += 1; containers += 1
                guard depth <= 32, containers <= 20_000 else { throw StremioAPIError.responseTooLarge }
            } else if byte == 125 || byte == 93 { depth -= 1 }
            else if byte == 44 {
                separators += 1
                guard separators <= 100_000 else { throw StremioAPIError.responseTooLarge }
            }
            if depth < 0 { throw StremioAPIError.invalidResponse }
        }
        guard depth == 0, !quoted else { throw StremioAPIError.invalidResponse }
    }

    private static func identifier(_ value: Any?, limit: Int = 256) -> Bool {
        guard let text = value as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              text != ".", text != "..", text.utf8.count <= limit else { return false }
        return !text.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }

    private static func array(_ object: [String: Any], key: String, limit: Int) throws -> [Any] {
        guard let value = object[key], !(value is NSNull) else { return [] }
        guard let entries = value as? [Any] else { throw StremioAPIError.invalidResponse }
        guard entries.count <= limit else { throw StremioAPIError.responseTooLarge }
        return entries
    }

    private static func strings(_ object: [String: Any], key: String, limit: Int, length: Int = 256) throws {
        for value in try array(object, key: key, limit: limit) {
            guard identifier(value, limit: length) else { throw StremioAPIError.invalidResponse }
        }
    }

    private static func manifest(_ object: [String: Any]) throws {
        guard identifier(object["id"]) else { throw StremioAPIError.invalidResponse }
        try strings(object, key: "types", limit: 32, length: 64)
        try strings(object, key: "idPrefixes", limit: 256)
        for entry in try array(object, key: "resources", limit: 16) {
            if let simple = entry as? String {
                guard identifier(simple, limit: 64) else { throw StremioAPIError.invalidResponse }
            } else if let resource = entry as? [String: Any] {
                guard identifier(resource["name"], limit: 64) else { throw StremioAPIError.invalidResponse }
                try strings(resource, key: "types", limit: 32, length: 64)
                try strings(resource, key: "idPrefixes", limit: 256)
            } else { throw StremioAPIError.invalidResponse }
        }
        var catalogKeys = Set<String>()
        for entry in try array(object, key: "catalogs", limit: 128) {
            guard let catalog = entry as? [String: Any], identifier(catalog["id"], limit: 512),
                  identifier(catalog["type"], limit: 64) else { throw StremioAPIError.invalidResponse }
            // Components are separated unambiguously; duplicate catalogue IDs
            // within a type cannot create duplicate SwiftUI focus identities.
            let key = "\(catalog["type"] as! String)\u{0}\(catalog["id"] as! String)"
            guard catalogKeys.insert(key).inserted else { throw StremioAPIError.invalidResponse }
            try strings(catalog, key: "extraRequired", limit: 32, length: 64)
            try strings(catalog, key: "extraSupported", limit: 32, length: 64)
            for value in try array(catalog, key: "extra", limit: 32) {
                guard let extra = value as? [String: Any], identifier(extra["name"], limit: 64) else {
                    throw StremioAPIError.invalidResponse
                }
                try strings(extra, key: "options", limit: 2_048, length: 512)
            }
        }
    }

    private static func validMeta(_ meta: [String: Any]) -> Bool {
        identifier(meta["id"], limit: 512)
            && (meta["type"] == nil || identifier(meta["type"], limit: 64))
            && (meta["name"] == nil || identifier(meta["name"], limit: 1_024))
    }

    private static func metaCollections(_ meta: [String: Any]) throws {
        _ = try array(meta, key: "videos", limit: 5_000)
        _ = try array(meta, key: "cast", limit: 256)
        _ = try array(meta, key: "genres", limit: 128)
    }

    private static func cleanMeta(_ meta: inout [String: Any], source: URL, changed: inout Bool) {
        cleanLinks(&meta, keys: ["poster", "posterFallback", "background", "logo"], source: source, changed: &changed)
        if let entries = meta["videos"] as? [Any] {
            meta["videos"] = entries.map { value -> Any in
                guard var video = value as? [String: Any] else { return value }
                cleanLinks(&video, keys: ["thumbnail"], source: source, changed: &changed)
                return video
            }
        }
    }

    private static func cleanLinks(_ object: inout [String: Any], keys: [String], source: URL, changed: inout Bool) {
        for key in keys {
            guard let value = object[key], !(value is NSNull) else { continue }
            guard let raw = value as? String, NTVAddonLinkPolicy.permits(raw, source: source) else {
                object.removeValue(forKey: key); changed = true; continue
            }
        }
    }

    private static func cleanHeaders(_ stream: inout [String: Any], changed: inout Bool) {
        guard var hints = stream["behaviorHints"] as? [String: Any],
              var proxy = hints["proxyHeaders"] as? [String: Any], let request = proxy["request"] else { return }
        guard let headers = request as? [String: String], headers.count <= 32 else {
            proxy.removeValue(forKey: "request"); hints["proxyHeaders"] = proxy
            stream["behaviorHints"] = hints; changed = true; return
        }
        let forbidden = Set(["host", "content-length", "transfer-encoding", "connection", "upgrade", "proxy-authorization", "proxy-connection", "te", "trailer"])
        let token = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!#$%&'*+-.^_`|~")
        var total = 0
        let checked = headers.filter { name, value in
            total += name.utf8.count + value.utf8.count
            let allowed = !name.isEmpty && name.utf8.count <= 128 && name.unicodeScalars.allSatisfy({ token.contains($0) })
                && !forbidden.contains(name.lowercased()) && value.utf8.count <= 8_192
                && !value.unicodeScalars.contains { $0.value < 32 || $0.value == 127 }
            if !allowed { changed = true }
            return allowed
        }
        if total > 16_384 { proxy.removeValue(forKey: "request"); changed = true }
        else { proxy["request"] = checked }
        hints["proxyHeaders"] = proxy; stream["behaviorHints"] = hints
    }
}
