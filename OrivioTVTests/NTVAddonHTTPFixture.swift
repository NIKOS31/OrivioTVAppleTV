import Foundation
import Network

/// A real loopback server checks URLSession redirects and automatic cookies,
/// rather than relying on URLProtocol's simulated redirect behaviour.
final class NTVAddonHTTPFixture: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "ntv.test.addon-origin")
    private let lock = NSLock()
    private var received: [String] = []
    var requests: [String] { lock.lock(); defer { lock.unlock() }; return received }
    private func note(_ text: String) { lock.lock(); received.append(text); lock.unlock() }

    init(redirectTo: URL? = nil, redirectWithinOrigin: Bool = false) throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        listener = try NWListener(using: parameters)
        let callbackQueue = queue
        listener.newConnectionHandler = { [weak self] connection in
            connection.start(queue: callbackQueue)
            self?.receive(connection, bytes: Data(), redirectTo: redirectTo, withinOrigin: redirectWithinOrigin)
        }
    }

    private func receive(_ connection: NWConnection, bytes: Data, redirectTo: URL?, withinOrigin: Bool) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, complete, error in
            guard let self, error == nil, let data else { connection.cancel(); return }
            let accumulated = bytes + data
            guard accumulated.count <= 8192 else { connection.cancel(); return }
            guard accumulated.range(of: Data("\r\n\r\n".utf8)) != nil else {
                if complete { connection.cancel(); return }
                self.receive(connection, bytes: accumulated, redirectTo: redirectTo, withinOrigin: withinOrigin)
                return
            }
            guard let text = String(data: accumulated, encoding: .utf8) else { connection.cancel(); return }
            self.note(text)
            let firstPath = text.hasPrefix("GET /response ")
            let location = redirectTo?.absoluteString ?? (withinOrigin && firstPath ? "/next" : nil)
            let body = location == nil ? "{}" : ""
            let status = location == nil ? "200 OK" : "302 Found"
            let extra = location.map { "Location: \($0)\r\n" } ?? ""
            let reply = Data("HTTP/1.1 \(status)\r\nContent-Type: application/json\r\n\(extra)Content-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)".utf8)
            connection.send(content: reply, completion: .contentProcessed { _ in connection.cancel() })
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
