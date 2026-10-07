import Foundation

/// A cancellable device-code flow. Its state contains no credentials and can
/// be presented by a future TV connection screen without a browser on tvOS.
struct NTVTwitchAuthorization {
    typealias Sleep = (UInt64) async throws -> Void
    let api: NTVTwitchAPI
    var now: () -> Date = Date.init
    var sleep: Sleep = { try await Task.sleep(nanoseconds: $0) }

    struct Ticket {
        let code: NTVTwitchDeviceCode
        let expiresAt: Date
    }

    func begin() async throws -> Ticket {
        let code = try await api.beginDeviceAuthorization()
        return Ticket(code: code, expiresAt: now().addingTimeInterval(Double(code.expiresIn)))
    }

    func complete(_ ticket: Ticket) async throws -> (NTVTwitchTokens, NTVTwitchIdentity) {
        var interval = max(1, ticket.code.interval)
        while now() < ticket.expiresAt {
            try Task.checkCancellation()
            let remaining = ticket.expiresAt.timeIntervalSince(now())
            guard remaining > Double(interval) else { throw NTVTwitchError.expiredCode }
            try await sleep(UInt64(interval) * 1_000_000_000)
            try Task.checkCancellation()
            guard now() < ticket.expiresAt else { throw NTVTwitchError.expiredCode }
            do {
                let tokens = try await api.pollDeviceAuthorization(ticket.code)
                let identity = try await api.validate(tokens.accessToken)
                return (tokens, identity)
            } catch NTVTwitchError.authorizationPending {
                continue
            } catch NTVTwitchError.slowDown {
                interval += 5
            }
        }
        throw NTVTwitchError.expiredCode
    }
}

/// Serialises refreshes for one profile so a rotating public-client refresh
/// token cannot be exchanged twice. It is deliberately independent of the
/// movie/addon account manager and is started only while the Twitch UI is used.
actor NTVTwitchSession {
    struct Storage {
        let load: () throws -> NTVTwitchTokens?
        let save: (NTVTwitchTokens) throws -> Void
        let remove: () throws -> Void

        init(_ credentials: NTVTwitchCredentials) {
            load = credentials.load
            save = credentials.save
            remove = credentials.remove
        }
        init(load: @escaping () throws -> NTVTwitchTokens?,
             save: @escaping (NTVTwitchTokens) throws -> Void,
             remove: @escaping () throws -> Void) {
            self.load = load; self.save = save; self.remove = remove
        }
    }
    private let api: NTVTwitchAPI
    private let storage: Storage
    private let now: () -> Date
    private var tokens: NTVTwitchTokens?
    private var identity: NTVTwitchIdentity?
    private var validatedAt: Date?
    private var exchange: Task<NTVTwitchTokens, Error>?
    private var generation = 0

    init(api: NTVTwitchAPI, storage: Storage, now: @escaping () -> Date = Date.init) throws {
        self.api = api; self.storage = storage; self.now = now
        tokens = try storage.load()
    }

    func adopt(tokens: NTVTwitchTokens) async throws -> NTVTwitchIdentity {
        let expected = generation
        let result = try await api.validate(tokens.accessToken)
        try Task.checkCancellation()
        guard expected == generation else { throw CancellationError() }
        try storage.save(tokens)
        generation += 1
        exchange?.cancel(); exchange = nil
        self.tokens = tokens; identity = result; validatedAt = now()
        return result
    }

    /// Call when the feature enters the foreground, then once per hour while
    /// its UI remains active. API requests also validate if that deadline passed.
    func validateSession() async throws -> NTVTwitchIdentity {
        guard let tokens else { throw NTVTwitchError.unauthorized }
        let expected = generation
        do {
            let result = try await api.validate(tokens.accessToken)
            guard expected == generation else { throw CancellationError() }
            identity = result; validatedAt = now()
            return result
        } catch NTVTwitchError.unauthorized {
            guard expected == generation else { throw CancellationError() }
            return try await renew(rejectedToken: tokens.accessToken)
        } catch NTVTwitchError.invalidIdentity {
            guard expected == generation else { throw CancellationError() }
            try clear()
            throw NTVTwitchError.invalidIdentity
        }
    }

    func followedStreams(after: String? = nil) async throws -> NTVTwitchPage<NTVTwitchStream> {
        let expected = generation
        let state = try await authorizedState()
        guard expected == generation else { throw CancellationError() }
        do {
            let page = try await api.followedStreams(accessToken: state.0.accessToken, userID: state.1.userID!, after: after)
            guard expected == generation else { throw CancellationError() }
            return page
        }
        catch NTVTwitchError.unauthorized {
            guard expected == generation else { throw CancellationError() }
            let user = try await renew(rejectedToken: state.0.accessToken)
            guard let current = tokens else { throw NTVTwitchError.unauthorized }
            let page = try await api.followedStreams(accessToken: current.accessToken, userID: user.userID!, after: after)
            guard expected == generation else { throw CancellationError() }
            return page
        }
    }

    func searchChannels(_ query: String, liveOnly: Bool = false, after: String? = nil) async throws -> NTVTwitchPage<NTVTwitchChannel> {
        let expected = generation
        let state = try await authorizedState()
        guard expected == generation else { throw CancellationError() }
        do {
            let page = try await api.searchChannels(query, accessToken: state.0.accessToken, liveOnly: liveOnly, after: after)
            guard expected == generation else { throw CancellationError() }
            return page
        }
        catch NTVTwitchError.unauthorized {
            guard expected == generation else { throw CancellationError() }
            _ = try await renew(rejectedToken: state.0.accessToken)
            guard let current = tokens else { throw NTVTwitchError.unauthorized }
            let page = try await api.searchChannels(query, accessToken: current.accessToken, liveOnly: liveOnly, after: after)
            guard expected == generation else { throw CancellationError() }
            return page
        }
    }

    func disconnect() async throws {
        let old = tokens?.accessToken
        var localFailure: Error?
        do { try clear() } catch { localFailure = error }
        // Even a failed local deletion must not skip revocation at Twitch.
        if let old {
            do { try await api.revoke(old) }
            catch { if localFailure == nil { throw error } }
        }
        if let localFailure { throw localFailure }
    }

    private func authorizedState() async throws -> (NTVTwitchTokens, NTVTwitchIdentity) {
        if identity == nil || validatedAt == nil || now().timeIntervalSince(validatedAt!) >= 3600 {
            _ = try await validateSession()
        }
        guard let tokens, let identity else { throw NTVTwitchError.unauthorized }
        return (tokens, identity)
    }

    private func renew(rejectedToken: String) async throws -> NTVTwitchIdentity {
        guard let previous = tokens else { throw NTVTwitchError.unauthorized }
        if previous.accessToken != rejectedToken, let identity { return identity }
        let expected = generation
        let task: Task<NTVTwitchTokens, Error>
        if let exchange { task = exchange }
        else {
            let api = api
            task = Task { try await api.refresh(previous.refreshToken) }
            exchange = task
        }
        do {
            let updated = try await task.value
            guard expected == generation else { throw CancellationError() }
            // Persist the rotated refresh token even if the subsequent
            // validation encounters a temporary network error.
            try storage.save(updated)
            tokens = updated
            let result = try await api.validate(updated.accessToken)
            guard expected == generation else { throw CancellationError() }
            if let oldUser = identity?.userID, oldUser != result.userID { throw NTVTwitchError.invalidIdentity }
            identity = result; validatedAt = now(); exchange = nil
            return result
        } catch {
            guard expected == generation else { throw CancellationError() }
            exchange = nil
            if error as? NTVTwitchError == .unauthorized || error as? NTVTwitchError == .invalidIdentity { try clear() }
            throw error
        }
    }

    private func clear() throws {
        generation += 1
        exchange?.cancel(); exchange = nil
        tokens = nil; identity = nil; validatedAt = nil
        try storage.remove()
    }
}
