import Foundation

/// Official OAuth/Helix endpoints only. No playback URL resolver is implied
/// by these metadata models. The app does not start this client until its own
/// public Twitch application has been registered and a UI is wired to it.
struct NTVTwitchAPI {
    typealias Transport = (URLRequest) async throws -> (Data, HTTPURLResponse)
    static let followedScope = "user:read:follows"
    let clientID: String
    private let transport: Transport

    init(clientID: String, transport: @escaping Transport = NTVTwitchAPI.send) throws {
        let clean = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else {
            throw NTVTwitchError.unconfigured
        }
        self.clientID = clean
        self.transport = transport
    }

    func beginDeviceAuthorization() async throws -> NTVTwitchDeviceCode {
        let code: NTVTwitchDeviceCode = try await oauth("device", fields: [
            "client_id": clientID, "scopes": Self.followedScope
        ])
        guard code.expiresIn > 0, code.expiresIn <= 86400, code.interval > 0,
              code.interval <= min(code.expiresIn, 3600), !code.deviceCode.isEmpty, !code.userCode.isEmpty,
              let url = URL(string: code.verificationURI), url.scheme == "https",
              ["www.twitch.tv", "twitch.tv"].contains(url.host ?? ""), url.path == "/activate",
              url.user == nil, url.password == nil, url.port == nil || url.port == 443 else {
            throw NTVTwitchError.invalidResponse
        }
        return code
    }

    /// One poll only. The caller must respect `interval`, expiry and cancellation.
    func pollDeviceAuthorization(_ code: NTVTwitchDeviceCode) async throws -> NTVTwitchTokens {
        let tokens: NTVTwitchTokens = try await oauth("token", fields: ["client_id": clientID, "scopes": Self.followedScope,
            "device_code": code.deviceCode, "grant_type": "urn:ietf:params:oauth:grant-type:device_code"])
        try checkTokens(tokens)
        return tokens
    }

    func refresh(_ refreshToken: String) async throws -> NTVTwitchTokens {
        // Public DCF clients do not send a client secret. Refresh tokens rotate.
        let tokens: NTVTwitchTokens = try await oauth("token", fields: ["client_id": clientID,
            "grant_type": "refresh_token", "refresh_token": refreshToken])
        try checkTokens(tokens)
        return tokens
    }

    func validate(_ accessToken: String) async throws -> NTVTwitchIdentity {
        var request = URLRequest(url: URL(string: "https://id.twitch.tv/oauth2/validate")!)
        request.setValue("OAuth \(accessToken)", forHTTPHeaderField: "Authorization")
        let identity: NTVTwitchIdentity = try await decoded(request)
        guard identity.expiresIn > 0 else { throw NTVTwitchError.unauthorized }
        guard identity.clientID == clientID, let userID = identity.userID, !userID.isEmpty,
              identity.scopes.contains(Self.followedScope) else { throw NTVTwitchError.invalidIdentity }
        return identity
    }

    func followedStreams(accessToken: String, userID: String, after: String? = nil) async throws -> NTVTwitchPage<NTVTwitchStream> {
        try await helix("streams/followed", accessToken: accessToken,
                        query: ["user_id": userID, "first": "40", "after": after])
    }

    func searchChannels(_ query: String, accessToken: String, liveOnly: Bool = false,
                        after: String? = nil) async throws -> NTVTwitchPage<NTVTwitchChannel> {
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return NTVTwitchPage(data: [], pagination: .init(cursor: nil)) }
        return try await helix("search/channels", accessToken: accessToken,
            query: ["query": clean, "live_only": liveOnly ? "true" : "false", "first": "40", "after": after])
    }

    func revoke(_ accessToken: String) async throws {
        var request = URLRequest(url: URL(string: "https://id.twitch.tv/oauth2/revoke")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.form(["client_id": clientID, "token": accessToken])
        _ = try await checked(request)
    }

    private func oauth<T: Decodable>(_ path: String, fields: [String: String]) async throws -> T {
        var request = URLRequest(url: URL(string: "https://id.twitch.tv/oauth2/\(path)")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.form(fields)
        return try await decoded(request)
    }

    private func helix<T: Decodable>(_ path: String, accessToken: String, query: [String: String?]) async throws -> T {
        var parts = URLComponents(string: "https://api.twitch.tv/helix/\(path)")!
        parts.queryItems = query.sorted { $0.key < $1.key }.compactMap { key, value in
            value.map { URLQueryItem(name: key, value: $0) }
        }
        var request = URLRequest(url: parts.url!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(clientID, forHTTPHeaderField: "Client-Id")
        return try await decoded(request)
    }

    private func decoded<T: Decodable>(_ request: URLRequest) async throws -> T {
        let data = try await checked(request)
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw NTVTwitchError.invalidResponse }
    }

    private func checked(_ request: URLRequest) async throws -> Data {
        try Task.checkCancellation()
        let (data, response) = try await transport(request)
        try Task.checkCancellation()
        guard (200..<300).contains(response.statusCode) else {
            // Never propagate a server body: it may contain account identifiers.
            let message = (try? JSONDecoder().decode(OAuthFailure.self, from: data))?.message
            if response.statusCode == 400 {
                switch message {
                case "authorization_pending": throw NTVTwitchError.authorizationPending
                case "slow_down": throw NTVTwitchError.slowDown
                case "access_denied": throw NTVTwitchError.denied
                case "expired_token", "invalid device code": throw NTVTwitchError.expiredCode
                case "Invalid refresh token": throw NTVTwitchError.unauthorized
                default: break
                }
            }
            if response.statusCode == 401 { throw NTVTwitchError.unauthorized }
            if response.statusCode == 429 { throw NTVTwitchError.rateLimited }
            throw NTVTwitchError.http(response.statusCode)
        }
        return data
    }

    private struct OAuthFailure: Decodable { let message: String? }
    private func checkTokens(_ tokens: NTVTwitchTokens) throws {
        guard !tokens.accessToken.isEmpty, !tokens.refreshToken.isEmpty, tokens.expiresIn > 0,
              tokens.tokenType.lowercased() == "bearer" else { throw NTVTwitchError.invalidResponse }
    }
    private static func form(_ values: [String: String]) -> Data {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        let pairs = values.sorted { $0.key < $1.key }.map {
            "\($0.key.addingPercentEncoding(withAllowedCharacters: allowed)!)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed)!)"
        }
        return Data(pairs.joined(separator: "&").utf8)
    }

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 40
        return URLSession(configuration: config, delegate: TwitchRedirectGuard(), delegateQueue: nil)
    }()
    private static func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            return try await NTVBoundedResponse.data(for: request, session: session, maximumBytes: 1 << 20)
        } catch is NTVBoundedResponse.Failure { throw NTVTwitchError.invalidResponse }
    }
}

private final class TwitchRedirectGuard: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        // None of the OAuth/Helix calls requires a redirect. Keep tokens on
        // their exact endpoint even if an upstream responds unexpectedly.
        completionHandler(nil)
    }
}

struct NTVTwitchDeviceCode: Decodable {
    let deviceCode: String
    let expiresIn: Int
    let interval: Int
    let userCode: String
    let verificationURI: String
    enum CodingKeys: String, CodingKey {
        case deviceCode = "device_code", expiresIn = "expires_in", interval
        case userCode = "user_code", verificationURI = "verification_uri"
    }
}

struct NTVTwitchTokens: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int
    let scope: [String]
    let tokenType: String
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token", refreshToken = "refresh_token", expiresIn = "expires_in", scope
        case tokenType = "token_type"
    }
}

struct NTVTwitchIdentity: Decodable {
    let clientID: String
    let login: String?
    let userID: String?
    let scopes: [String]
    let expiresIn: Int
    enum CodingKeys: String, CodingKey {
        case clientID = "client_id", login, userID = "user_id", scopes, expiresIn = "expires_in"
    }
}

struct NTVTwitchPage<Item: Decodable>: Decodable {
    struct Pagination: Decodable { let cursor: String? }
    let data: [Item]
    let pagination: Pagination
}

struct NTVTwitchStream: Decodable, Identifiable {
    let id: String
    let userID: String
    let userLogin: String
    let userName: String
    let gameName: String
    let title: String
    let viewerCount: Int
    let thumbnailURL: String
    var previewURL: URL? {
        URL(string: thumbnailURL.replacingOccurrences(of: "{width}", with: "480")
            .replacingOccurrences(of: "{height}", with: "270"))
    }
    enum CodingKeys: String, CodingKey {
        case id, userID = "user_id", userLogin = "user_login", userName = "user_name"
        case gameName = "game_name", title, viewerCount = "viewer_count", thumbnailURL = "thumbnail_url"
    }
}

struct NTVTwitchChannel: Decodable, Identifiable {
    let id: String
    let broadcasterLogin: String
    let displayName: String
    let gameName: String
    let isLive: Bool
    let thumbnailURL: String
    let title: String
    enum CodingKeys: String, CodingKey {
        case id, broadcasterLogin = "broadcaster_login", displayName = "display_name", gameName = "game_name"
        case isLive = "is_live", thumbnailURL = "thumbnail_url", title
    }
}

enum NTVTwitchError: Error, LocalizedError, Equatable {
    case unconfigured, invalidResponse, invalidIdentity, authorizationPending, slowDown
    case denied, expiredCode, unauthorized, rateLimited, http(Int), secureStorage
    var errorDescription: String? {
        switch self {
        case .unconfigured: return "La connexion Twitch n’est pas encore configurée."
        case .invalidResponse: return "La réponse de Twitch est incomplète. Réessayez."
        case .invalidIdentity: return "Cette autorisation ne correspond pas à nTV. Reconnectez Twitch."
        case .authorizationPending: return "Validez la connexion sur votre téléphone."
        case .slowDown, .rateLimited: return "Twitch demande de patienter avant de réessayer."
        case .denied: return "La connexion Twitch a été refusée."
        case .expiredCode: return "Le code a expiré. Demandez un nouveau code."
        case .unauthorized: return "Reconnectez votre compte Twitch."
        case .http: return "Twitch est momentanément indisponible."
        case .secureStorage: return "La connexion n’a pas pu être enregistrée sur cet appareil."
        }
    }
}
