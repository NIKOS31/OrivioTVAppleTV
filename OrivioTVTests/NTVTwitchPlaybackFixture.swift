import Foundation

actor NTVTwitchPlaybackFixture {
    enum Mode { case valid, denied, expired, wrongChannel, http(Int) }
    private var requests: [URLRequest] = []
    let mode: Mode
    init(_ mode: Mode = .valid) { self.mode = mode }
    func recorded() -> [URLRequest] { requests }
    func send(_ request: URLRequest, _ limit: Int) throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let url = request.url!
        var status = 200
        let data: Data
        if case .http(let code) = mode {
            status = code
            data = Data("PRIVATE-VIDEO-ERROR-SENTINEL".utf8)
        } else if url.host == "gql.twitch.tv" {
            var channel = "fixture_channel", expires = 2000, denied = false
            switch mode {
            case .denied: denied = true
            case .expired: expires = 999
            case .wrongChannel: channel = "another_channel"
            default: break
            }
            let claims = try JSONSerialization.data(withJSONObject: ["channel": channel, "expires": expires,
                "authorization": ["forbidden": denied], "private": ["allowed_to_view": !denied], "geoblock_reason": ""])
            data = try JSONSerialization.data(withJSONObject: ["data": ["playback": ["signature": "video-fixture-signature",
                "value": String(data: claims, encoding: .utf8)!]]])
        } else {
            data = Data("#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1200000\nhttps://video-weaver.fixture.hls.ttvnw.net/playlist.m3u8\n".utf8)
        }
        return (data, HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!)
    }
}

actor NTVTwitchVideoGate {
    let started: () -> Void
    private var continuation: CheckedContinuation<URL, Never>?
    init(started: @escaping () -> Void) { self.started = started }
    func wait() async -> URL {
        started()
        return await withCheckedContinuation { continuation = $0 }
    }
    func finish(_ url: URL) { continuation?.resume(returning: url); continuation = nil }
}
