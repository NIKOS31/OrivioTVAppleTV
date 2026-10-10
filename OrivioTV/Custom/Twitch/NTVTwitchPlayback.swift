import Foundation

struct NTVTwitchQuality: Equatable, Identifiable {
    let id: String
    let label: String
    let url: URL
    let height: Int
    let frameRate: Double
    let bandwidth: Double
}

struct NTVTwitchMedia {
    let masterURL: URL
    let qualities: [NTVTwitchQuality]
}

/// Experimental anonymous public-video protocol, separate from nTV's official
/// OAuth/Helix client. No account token, cookie or integrity workaround enters it.
/// Twitch does not provide a supported third-party native playback API.
struct NTVTwitchPlayback {
    typealias Transport = (URLRequest, Int) async throws -> (Data, HTTPURLResponse)
    private let transport: Transport
    private let now: () -> Date
    // Public website player identifier also used by the Streamlink protocol.
    // This is not nTV's registered OAuth client, nor a secret from a user.
    private static let videoClientID = "kimne78kx3ncx6brgo4mv6wki5h1ko"

    init(transport: @escaping Transport = NTVTwitchPlayback.send, now: @escaping () -> Date = Date.init) {
        self.transport = transport; self.now = now
    }

    func resolve(channel raw: String) async throws -> URL {
        try await resolveMedia(channel: raw).masterURL
    }

    func resolveMedia(channel raw: String) async throws -> NTVTwitchMedia {
        let login = raw.lowercased()
        guard !login.isEmpty, login.utf8.count <= 25,
              login.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }) else {
            throw Failure.invalidChannel
        }
        try Task.checkCancellation()
        var request = URLRequest(url: URL(string: "https://gql.twitch.tv/gql")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.videoClientID, forHTTPHeaderField: "Client-ID")
        let query = "query NTVPublicLive($channel: String!) { playback: streamPlaybackAccessToken(channelName: $channel, params: {platform: \"web\", playerBackend: \"mediaplayer\", playerType: \"embed\"}) { signature value } }"
        request.httpBody = try JSONSerialization.data(withJSONObject: ["query": query, "variables": ["channel": login]])
        let payload = try await checked(request, limit: 64 << 10)
        guard let ticket = try? JSONDecoder().decode(Envelope.self, from: payload).data?.playback,
              !ticket.signature.isEmpty, ticket.signature.utf8.count <= 512,
              ticket.value.utf8.count <= 32 << 10,
              let claims = try? JSONDecoder().decode(Claims.self, from: Data(ticket.value.utf8)),
              claims.channel?.lowercased() == login, let expiry = claims.expires, expiry.isFinite,
              expiry > now().timeIntervalSince1970, expiry < now().timeIntervalSince1970 + 6 * 3600 else {
            throw Failure.protocolChanged
        }
        // Respect access decisions. Never change token claims, hide ads, acquire
        // a browser integrity token, or retry with account cookies/credentials.
        guard claims.authorization?.forbidden == false, claims.privateAccess?.allowedToView != false,
              claims.geoblockReason?.isEmpty != false else { throw Failure.denied }
        var components = URLComponents(string: "https://usher.ttvnw.net/api/v2/channel/hls/\(login).m3u8")!
        components.queryItems = [
            .init(name: "sig", value: ticket.signature), .init(name: "token", value: ticket.value),
            .init(name: "allow_source", value: "true"), .init(name: "allow_audio_only", value: "true"),
            .init(name: "supported_codecs", value: "h264"), .init(name: "platform", value: "web")
        ]
        guard let url = components.url else { throw Failure.protocolChanged }
        let playlist = try await checked(URLRequest(url: url), limit: 512 << 10)
        try Self.validatePlaylist(playlist, base: url)
        try Task.checkCancellation()
        return NTVTwitchMedia(masterURL: url, qualities: try Self.qualities(in: playlist, base: url))
    }

    /// Only variants advertised in the validated master playlist are offered.
    /// URLs stay in memory and never enter labels, preferences or logs.
    static func qualities(in data: Data, base: URL) throws -> [NTVTwitchQuality] {
        try validatePlaylist(data, base: base)
        guard let text = String(data: data, encoding: .utf8) else { throw Failure.protocolChanged }
        let expression = try NSRegularExpression(pattern: "([A-Z0-9-]+)=(\"[^\"]*\"|[^,]*)")
        func attributes(_ line: String) -> [String: String] {
            var values: [String: String] = [:]
            for match in expression.matches(in: line, range: NSRange(line.startIndex..., in: line)) {
                guard let key = Range(match.range(at: 1), in: line), let value = Range(match.range(at: 2), in: line) else { continue }
                values[String(line[key])] = String(line[value]).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            }
            return values
        }
        var pending: [String: String]?
        var results: [NTVTwitchQuality] = []
        var seen = Set<URL>()
        for part in text.split(whereSeparator: \.isNewline) {
            let line = String(part).trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("#EXT-X-STREAM-INF:") { pending = attributes(line); continue }
            guard !line.isEmpty, !line.hasPrefix("#"), let values = pending else { continue }
            pending = nil
            if values["VIDEO"] == "audio_only" { continue }
            if let codecs = values["CODECS"], !codecs.contains("avc1"), !codecs.contains("hvc1"), !codecs.contains("hev1") { continue }
            guard let url = URL(string: line, relativeTo: base)?.absoluteURL, permitsMediaURL(url) else { throw Failure.protocolChanged }
            let height = values["RESOLUTION"]?.split(separator: "x").last.flatMap { Int($0) } ?? 0
            let fps = Double(values["FRAME-RATE"] ?? "0") ?? 0
            let bandwidth = Double(values["BANDWIDTH"] ?? "0") ?? 0
            guard (0...4320).contains(height), fps.isFinite, (0...240).contains(fps), bandwidth.isFinite, bandwidth >= 0 else { throw Failure.protocolChanged }
            let label = height > 0 ? "\(height)p" + (fps > 30 ? "\(Int(fps.rounded()))" : "") : "Source"
            guard seen.insert(url).inserted, results.count < 16 else { continue }
            results.append(.init(id: "variant-\(results.count)", label: label, url: url,
                                 height: height, frameRate: fps, bandwidth: bandwidth))
        }
        return results.sorted { a, b in
            if a.height != b.height { return a.height > b.height }
            if a.frameRate != b.frameRate { return a.frameRate > b.frameRate }
            return a.bandwidth > b.bandwidth
        }
    }

    private func checked(_ request: URLRequest, limit: Int) async throws -> Data {
        try Task.checkCancellation()
        let (body, response) = try await transport(request, limit)
        try Task.checkCancellation()
        guard body.count <= limit else { throw Failure.protocolChanged }
        switch response.statusCode {
        case 200..<300: return body
        case 401, 403: throw Failure.denied
        case 404: throw Failure.offline
        case 429: throw Failure.rateLimited
        default: throw Failure.unavailable
        }
    }

    static func permitsMediaURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", url.user == nil, url.password == nil,
              url.port == nil || url.port == 443, let host = url.host?.lowercased() else { return false }
        return host == "ttvnw.net" || host.hasSuffix(".ttvnw.net")
    }

    static func validatePlaylist(_ data: Data, base: URL) throws {
        guard let text = String(data: data, encoding: .utf8), text.hasPrefix("#EXTM3U"),
              permitsMediaURL(base) else { throw Failure.protocolChanged }
        var variants = 0
        let uri = try NSRegularExpression(pattern: "\\bURI=\"([^\"]+)\"")
        for part in text.split(whereSeparator: \.isNewline) {
            let line = String(part).trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("#") {
                for match in uri.matches(in: line, range: NSRange(line.startIndex..., in: line)) {
                    guard let range = Range(match.range(at: 1), in: line),
                          let target = URL(string: String(line[range]), relativeTo: base)?.absoluteURL,
                          permitsMediaURL(target) else { throw Failure.protocolChanged }
                }
            } else if !line.isEmpty {
                guard let target = URL(string: line, relativeTo: base)?.absoluteURL,
                      permitsMediaURL(target) else { throw Failure.protocolChanged }
                variants += 1
            }
        }
        guard variants > 0 else { throw Failure.offline }
    }

    private struct Envelope: Decodable {
        struct Body: Decodable { let playback: Ticket? }
        let data: Body?
    }
    private struct Ticket: Decodable { let signature: String; let value: String }
    private struct Claims: Decodable {
        struct Authorization: Decodable { let forbidden: Bool? }
        struct PrivateAccess: Decodable {
            let allowedToView: Bool?
            enum CodingKeys: String, CodingKey { case allowedToView = "allowed_to_view" }
        }
        let channel: String?; let expires: Double?; let authorization: Authorization?
        let privateAccess: PrivateAccess?; let geoblockReason: String?
        enum CodingKeys: String, CodingKey {
            case channel, expires, authorization, privateAccess = "private", geoblockReason = "geoblock_reason"
        }
    }
    private static let session = NTVAuthenticatedSession.make(timeout: 20)
    private static func send(_ request: URLRequest, limit: Int) async throws -> (Data, HTTPURLResponse) {
        try await NTVBoundedResponse.data(for: request, session: session, maximumBytes: limit)
    }

    enum Failure: Error, LocalizedError {
        case invalidChannel, protocolChanged, denied, offline, rateLimited, unavailable
        var errorDescription: String? {
            switch self {
            case .invalidChannel: return "Cette chaîne Twitch est invalide."
            case .offline: return "Cette chaîne n’est plus en direct."
            case .denied: return "Twitch ne permet pas la lecture de ce direct pour le moment."
            case .rateLimited: return "Twitch demande de patienter. Réessayez dans un instant."
            case .protocolChanged, .unavailable: return "La lecture Twitch est momentanément indisponible. Réessayez."
            }
        }
    }
}
