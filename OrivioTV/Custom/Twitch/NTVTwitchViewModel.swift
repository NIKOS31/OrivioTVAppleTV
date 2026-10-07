import Foundation
import Combine

@MainActor
final class NTVTwitchViewModel: ObservableObject {
    enum Phase: Equatable { case loading, disconnected, authorizing, connected, failed }
    @Published private(set) var phase: Phase = .loading
    @Published private(set) var identity: NTVTwitchIdentity?
    @Published private(set) var ticket: NTVTwitchAuthorization.Ticket?
    @Published private(set) var streams: [NTVTwitchStream] = []
    @Published private(set) var channels: [NTVTwitchChannel] = []
    @Published private(set) var message: String?
    @Published private(set) var loadingPage = false
    @Published private(set) var followedCursor: String?
    @Published private(set) var searchCursor: String?

    typealias SessionFactory = (NTVTwitchAPI, Int, String) throws -> NTVTwitchSession
    private let api: NTVTwitchAPI
    private let makeSession: SessionFactory
    private var session: NTVTwitchSession?
    private var flowTask: Task<Void, Never>?
    private var pageTask: Task<Void, Never>?
    private var epoch = 0
    private var pageEpoch = 0
    private var followedPages: Set<String> = []
    private var searchPages: Set<String> = []
    private var lastQuery = ""
    static let itemLimit = 400

    init(api: NTVTwitchAPI, makeSession: @escaping SessionFactory = { api, profile, owner in
        try NTVTwitchSession(api: api, storage: .init(NTVTwitchCredentials(
            clientID: api.clientID, profileID: profile, ownerScope: owner)))
    }) {
        self.api = api
        self.makeSession = makeSession
    }

    convenience init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ntvTwitchDemo") {
            let fixture = NTVTwitchUIDemo()
            let api = try! NTVTwitchAPI(clientID: NTVTwitchConfiguration.clientID,
                transport: { try await fixture.send($0) })
            self.init(api: api, makeSession: { api, _, _ in
                let memory = NTVTwitchDemoStorage()
                return try NTVTwitchSession(api: api, storage: .init(
                    load: { memory.tokens }, save: { memory.tokens = $0 }, remove: { memory.tokens = nil }))
            })
            return
        }
        #endif
        self.init(api: try! NTVTwitchAPI(clientID: NTVTwitchConfiguration.clientID))
    }

    func prepare(profileID: Int, ownerScope: String) async {
        leave()
        phase = .loading
        let expected = epoch
        do {
            let current = try makeSession(api, profileID, ownerScope)
            session = current
            let user = try await current.validateSession()
            try Task.checkCancellation()
            guard expected == epoch else { return }
            identity = user
            phase = .connected
            loadFollowed()
        } catch {
            guard expected == epoch, !Task.isCancelled else { return }
            if error as? NTVTwitchError == .unauthorized {
                phase = .disconnected
            } else {
                phase = .failed
                message = Self.displayError(error)
            }
        }
    }

    func connect() {
        guard phase == .disconnected, let current = session else { return }
        message = nil
        phase = .authorizing
        let expected = epoch
        let flow = NTVTwitchAuthorization(api: api)
        flowTask?.cancel()
        flowTask = Task { [weak self] in
            do {
                let ticket = try await flow.begin()
                try Task.checkCancellation()
                guard let self, self.epoch == expected else { return }
                self.ticket = ticket
                let result = try await flow.complete(ticket)
                try Task.checkCancellation()
                guard self.epoch == expected else { return }
                let user = try await current.adopt(tokens: result.0)
                guard self.epoch == expected, !Task.isCancelled else { return }
                self.identity = user
                self.ticket = nil
                self.phase = .connected
                self.loadFollowed()
            } catch {
                guard let self, self.epoch == expected, !Task.isCancelled else { return }
                self.ticket = nil
                self.phase = .disconnected
                self.message = Self.displayError(error)
            }
        }
    }

    func cancelConnection() {
        epoch &+= 1
        flowTask?.cancel()
        flowTask = nil
        ticket = nil
        phase = .disconnected
    }

    func disconnect() {
        guard let current = session else { return }
        epoch &+= 1
        pageEpoch &+= 1
        flowTask?.cancel(); pageTask?.cancel()
        identity = nil; ticket = nil; streams = []; channels = []
        followedCursor = nil; searchCursor = nil
        loadingPage = false; phase = .loading
        let expected = epoch
        pageTask = Task { [weak self] in
            var failure: String?
            do { try await current.disconnect() }
            catch { failure = Self.displayError(error) }
            guard let self, self.epoch == expected, !Task.isCancelled else { return }
            self.message = failure
            self.phase = .disconnected
        }
    }

    func loadFollowed(append: Bool = false) {
        guard phase == .connected, let current = session, !append || followedCursor != nil else { return }
        pageTask?.cancel()
        pageEpoch &+= 1
        let request = pageEpoch, expected = epoch
        let cursor = append ? followedCursor : nil
        if !append { streams = []; followedPages = [] }
        loadingPage = true; message = nil
        pageTask = Task { [weak self] in
            do {
                let page = try await current.followedStreams(after: cursor)
                guard let self, self.epoch == expected, self.pageEpoch == request, !Task.isCancelled else { return }
                var seen = Set(self.streams.map(\.id))
                self.streams += Array(page.data.filter { seen.insert($0.id).inserted }.prefix(max(0, Self.itemLimit - self.streams.count)))
                self.followedCursor = self.nextCursor(page.pagination.cursor, empty: page.data.isEmpty,
                    count: self.streams.count, previous: cursor, followed: true)
                self.loadingPage = false
            } catch { self?.finishFailure(error, epoch: expected, request: request) }
        }
    }

    func search(_ raw: String, append: Bool = false) {
        guard phase == .connected, let current = session else { return }
        let query = String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(256))
        guard !append || (query == lastQuery && searchCursor != nil) else { return }
        pageTask?.cancel()
        pageEpoch &+= 1
        let request = pageEpoch, expected = epoch
        let cursor = append ? searchCursor : nil
        if !append { channels = []; searchPages = []; searchCursor = nil; lastQuery = query }
        message = nil
        guard !query.isEmpty else { loadingPage = false; return }
        loadingPage = true
        pageTask = Task { [weak self] in
            do {
                let page = try await current.searchChannels(query, liveOnly: true, after: cursor)
                guard let self, self.epoch == expected, self.pageEpoch == request, !Task.isCancelled else { return }
                var seen = Set(self.channels.map(\.id))
                self.channels += Array(page.data.filter { seen.insert($0.id).inserted }.prefix(max(0, Self.itemLimit - self.channels.count)))
                self.searchCursor = self.nextCursor(page.pagination.cursor, empty: page.data.isEmpty,
                    count: self.channels.count, previous: cursor, followed: false)
                self.loadingPage = false
            } catch { self?.finishFailure(error, epoch: expected, request: request) }
        }
    }

    private func nextCursor(_ cursor: String?, empty: Bool, count: Int, previous: String?, followed: Bool) -> String? {
        guard !empty, count < Self.itemLimit, let cursor, !cursor.isEmpty, cursor != previous else { return nil }
        if followed { return followedPages.insert(cursor).inserted ? cursor : nil }
        return searchPages.insert(cursor).inserted ? cursor : nil
    }

    private func finishFailure(_ error: Error, epoch expected: Int, request: Int) {
        guard epoch == expected, pageEpoch == request, !(error is CancellationError) else { return }
        loadingPage = false
        message = Self.displayError(error)
        if error as? NTVTwitchError == .unauthorized || error as? NTVTwitchError == .invalidIdentity {
            identity = nil; streams = []; channels = []
            followedCursor = nil; searchCursor = nil
            phase = .disconnected
        }
    }

    private static func displayError(_ error: Error) -> String {
        (error as? NTVTwitchError)?.errorDescription ?? "Twitch est momentanément indisponible. Réessayez."
    }

    /// Twitch requires periodic validation. This task belongs to the visible
    /// screen and is cancelled when leaving it; no app-wide polling is added.
    func monitorSession() async {
        while !Task.isCancelled {
            do { try await Task.sleep(nanoseconds: 3300 * 1_000_000_000) }
            catch { return }
            guard phase == .connected, let current = session else { continue }
            let expected = epoch
            do {
                let user = try await current.validateSession()
                guard epoch == expected, !Task.isCancelled else { continue }
                identity = user
            } catch {
                guard epoch == expected, !Task.isCancelled else { continue }
                finishFailure(error, epoch: expected, request: pageEpoch)
            }
        }
    }

    func leave() {
        epoch &+= 1; pageEpoch &+= 1
        flowTask?.cancel(); pageTask?.cancel()
        flowTask = nil; pageTask = nil; session = nil
        identity = nil; ticket = nil; streams = []; channels = []
        followedCursor = nil; searchCursor = nil
        loadingPage = false; message = nil
    }
}

#if DEBUG
private final class NTVTwitchDemoStorage { var tokens: NTVTwitchTokens? }
private actor NTVTwitchUIDemo {
    private var polls = 0
    func send(_ request: URLRequest) throws -> (Data, HTTPURLResponse) {
        let path = request.url!.path
        var status = 200
        let json: [String: Any]
        switch path {
        case "/oauth2/device":
            polls = 0
            json = ["device_code": "fixture-device", "user_code": "NTVTEST", "expires_in": 1800,
                    "interval": 3, "verification_uri": "https://www.twitch.tv/activate?public=true&device-code=NTVTEST"]
        case "/oauth2/token":
            polls += 1
            if polls == 1 { status = 400; json = ["message": "authorization_pending"] }
            else { json = ["access_token": "fixture-access", "refresh_token": "fixture-refresh", "expires_in": 14400,
                           "scope": ["user:read:follows"], "token_type": "bearer"] }
        case "/oauth2/validate":
            json = ["client_id": NTVTwitchConfiguration.clientID, "user_id": "fixture-user", "login": "validation",
                    "scopes": ["user:read:follows"], "expires_in": 14400]
        case "/helix/streams/followed":
            json = ["data": [["id": "fixture-live", "user_id": "fixture-channel", "user_login": "validation",
                "user_name": "Validation Twitch", "game_name": "Discussion", "title": "Direct de validation",
                "viewer_count": 42, "thumbnail_url": ""]], "pagination": [:]]
        case "/helix/search/channels":
            json = ["data": [["id": "fixture-channel", "broadcaster_login": "validation", "display_name": "Validation Twitch",
                "game_name": "Discussion", "is_live": true, "title": "Direct de validation", "thumbnail_url": ""]], "pagination": [:]]
        default: json = [:]
        }
        return (try JSONSerialization.data(withJSONObject: json), HTTPURLResponse(url: request.url!,
            statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}
#endif
