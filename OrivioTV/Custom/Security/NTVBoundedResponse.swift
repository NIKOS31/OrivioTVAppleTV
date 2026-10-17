import Foundation

/// Collects decoded chunks with a hard budget, before building a complete body.
/// Per-task delegation reuses TLS connections and avoids a per-byte async loop.
enum NTVBoundedResponse {
    enum Failure: Error { case tooLarge, invalidResponse }

    static func data(for request: URLRequest, session: URLSession, maximumBytes: Int) async throws -> (Data, HTTPURLResponse) {
        precondition(maximumBytes > 0 && maximumBytes <= (16 << 20))
        try Task.checkCancellation()
        let receiver = Receiver(maximumBytes: maximumBytes, policy: session.delegate)
        let task = session.dataTask(with: request)
        task.delegate = receiver
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { receiver.start(task, continuation: $0) }
        } onCancel: { receiver.cancel(task) }
    }

    private final class Receiver: NSObject, URLSessionDataDelegate, @unchecked Sendable {
        typealias Reply = (Data, HTTPURLResponse)
        private let limit: Int
        private let policy: URLSessionDelegate?
        private let lock = NSLock()
        private var body = Data()
        private var response: HTTPURLResponse?
        private var continuation: CheckedContinuation<Reply, Error>?
        private var terminal: Result<Reply, Error>?

        init(maximumBytes: Int, policy: URLSessionDelegate?) { limit = maximumBytes; self.policy = policy }

        func start(_ task: URLSessionDataTask, continuation: CheckedContinuation<Reply, Error>) {
            lock.lock()
            if let result = terminal { lock.unlock(); continuation.resume(with: result); return }
            self.continuation = continuation
            lock.unlock()
            task.resume()
        }
        func cancel(_ task: URLSessionDataTask) {
            finish(.failure(CancellationError()))
            task.cancel()
        }
        private func finish(_ result: Result<Reply, Error>) {
            lock.lock()
            guard terminal == nil else { lock.unlock(); return }
            terminal = result
            let pending = continuation; continuation = nil
            body = Data(); response = nil
            lock.unlock()
            pending?.resume(with: result)
        }
        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
            guard let http = response as? HTTPURLResponse else {
                finish(.failure(Failure.invalidResponse)); completionHandler(.cancel); return
            }
            guard response.expectedContentLength <= Int64(limit) else {
                finish(.failure(Failure.tooLarge)); completionHandler(.cancel); return
            }
            lock.lock()
            let active = terminal == nil
            if active {
                self.response = http
                body.reserveCapacity(Int(min(max(response.expectedContentLength, 0), 64 << 10)))
            }
            lock.unlock()
            completionHandler(active ? .allow : .cancel)
        }
        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
            lock.lock()
            guard terminal == nil else { lock.unlock(); return }
            guard data.count <= limit - body.count else {
                lock.unlock(); finish(.failure(Failure.tooLarge)); dataTask.cancel(); return
            }
            body.append(data)
            lock.unlock()
        }
        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            lock.lock()
            let result: Result<Reply, Error>
            if let error { result = .failure(error) }
            else if let response { result = .success((body, response)) }
            else { result = .failure(Failure.invalidResponse) }
            lock.unlock()
            finish(result)
        }

        // A task delegate must preserve the caller's redirect/trust decisions.
        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                        completionHandler: @escaping (URLRequest?) -> Void) {
            if let delegate = policy as? URLSessionTaskDelegate,
               delegate.urlSession?(session, task: task, willPerformHTTPRedirection: response,
                                    newRequest: request, completionHandler: completionHandler) != nil { return }
            completionHandler(request)
        }
        func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
                        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
            if let delegate = policy as? URLSessionTaskDelegate,
               delegate.urlSession?(session, task: task, didReceive: challenge, completionHandler: completionHandler) != nil { return }
            if policy?.urlSession?(session, didReceive: challenge, completionHandler: completionHandler) != nil { return }
            completionHandler(.performDefaultHandling, nil)
        }
    }
}
