import Foundation
import Network

/// A slow, controllable response exercises URLSession's real chunk callbacks.
final class NTVBoundedHTTPProbe: @unchecked Sendable {
    let id: String
    let body: Data
    let declaredLength: Int?
    let stall: Bool
    let statusCode: Int
    let chunkSize: Int
    let chunkDelay: TimeInterval
    let onHeaders: () -> Void
    let onStop: () -> Void
    private let lock = NSLock()
    private var stopped = false
    private var sent = 0
    private var requestCount = 0
    var requestsReceived: Int { lock.lock(); defer { lock.unlock() }; return requestCount }
    var bytesSent: Int { lock.lock(); defer { lock.unlock() }; return sent }
    var isStopped: Bool { lock.lock(); defer { lock.unlock() }; return stopped }

    init(id: String = UUID().uuidString, body: Data = Data(), declaredLength: Int? = nil, stall: Bool = false,
         statusCode: Int = 200, chunkSize: Int = 256, chunkDelay: TimeInterval = 0.005,
         onHeaders: @escaping () -> Void = {}, onStop: @escaping () -> Void = {}) {
        self.id = id; self.statusCode = statusCode
        self.chunkSize = max(1, chunkSize); self.chunkDelay = max(0, chunkDelay)
        self.body = body; self.declaredLength = declaredLength; self.stall = stall
        self.onHeaders = onHeaders; self.onStop = onStop
    }
    func note(_ count: Int) { lock.lock(); sent += count; lock.unlock() }
    func noteRequest() { lock.lock(); requestCount += 1; lock.unlock() }
    func stop() {
        lock.lock()
        if stopped { lock.unlock(); return }
        stopped = true; lock.unlock(); onStop()
    }
}

final class NTVBoundedHTTPFixture: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var probes: [String: NTVBoundedHTTPProbe] = [:]
    private static let queue = DispatchQueue(label: "ntv.test.bounded-response")
    private var probe: NTVBoundedHTTPProbe?

    static func register(_ probe: NTVBoundedHTTPProbe) -> (URLSession, URLRequest) {
        lock.lock(); probes[probe.id] = probe; lock.unlock()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [NTVBoundedHTTPFixture.self]
        let url = URL(string: "https://bounded-fixture.invalid/" + probe.id)!
        return (URLSession(configuration: configuration), URLRequest(url: url))
    }
    static func remove(_ id: String) { lock.lock(); probes.removeValue(forKey: id); lock.unlock() }
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "bounded-fixture.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock(); probe = Self.probes[request.url!.lastPathComponent]; Self.lock.unlock()
        guard let probe else { client?.urlProtocol(self, didFailWithError: URLError(.badURL)); return }
        probe.noteRequest()
        var headers = ["Content-Type": "application/json"]
        if let length = probe.declaredLength { headers["Content-Length"] = String(length) }
        let response = HTTPURLResponse(url: request.url!, statusCode: probe.statusCode, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        probe.onHeaders()
        if !probe.stall { sendChunk(from: 0) }
    }
    private func sendChunk(from position: Int) {
        Self.queue.asyncAfter(deadline: .now() + (probe?.chunkDelay ?? 0.005)) { [weak self] in
            guard let self, let probe = self.probe, !probe.isStopped else { return }
            guard position < probe.body.count else { self.client?.urlProtocolDidFinishLoading(self); return }
            let end = min(position + probe.chunkSize, probe.body.count)
            let chunk = probe.body.subdata(in: position..<end)
            probe.note(chunk.count)
            self.client?.urlProtocol(self, didLoad: chunk)
            self.sendChunk(from: end)
        }
    }
    override func stopLoading() { probe?.stop() }
}

/// Real loopback HTTP is used for gzip: URLProtocol does not model wire decoding.
final class NTVGzipHTTPFixture: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "ntv.test.gzip-response")
    private let lock = NSLock()
    private var hits = 0
    var requestsReceived: Int { lock.lock(); defer { lock.unlock() }; return hits }
    private func noteRequest() { lock.lock(); hits += 1; lock.unlock() }
    init(payload: Data, redirectTo: URL? = nil) throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        listener = try NWListener(using: parameters)
        let status = redirectTo == nil ? "200 OK" : "302 Found"
        let extra = redirectTo.map { "Location: \($0.absoluteString)\r\n" } ?? "Content-Encoding: gzip\r\n"
        let head = Data("HTTP/1.1 \(status)\r\nContent-Type: application/json\r\n\(extra)Content-Length: \(payload.count)\r\nConnection: close\r\n\r\n".utf8)
        let response = head + payload
        let callbackQueue = queue
        listener.newConnectionHandler = { [weak self] connection in
            connection.start(queue: callbackQueue)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] _, _, _, error in
                guard error == nil else { connection.cancel(); return }
                self?.noteRequest()
                connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
            }
        }
    }
    func start() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    self.listener.stateUpdateHandler = nil
                    continuation.resume(returning: URL(string: "http://127.0.0.1:\(self.listener.port!.rawValue)/response")!)
                case .failed(let error):
                    self.listener.stateUpdateHandler = nil
                    continuation.resume(throwing: error)
                default: break
                }
            }
            listener.start(queue: queue)
        }
    }
    func stop() { listener.cancel() }
}
