import Foundation

/// One operation per key, with a process-wide window and independent waiters.
/// Cancelling one view releases that waiter immediately. Only the last waiter
/// cancels the shared operation; its slot stays occupied until work actually
/// stops, including decoders that cannot interrupt an ImageIO call.
actor NTVSharedWorkPool<Value: Sendable> {
    enum Priority: Int, Sendable { case background, visible }
    private struct Entry {
        let generation: UUID
        let work: @Sendable () async throws -> Value
        var priority: Priority
        var waiters: [UUID: CheckedContinuation<Value, Error>]
        var task: Task<Void, Never>?
    }
    private let limit: Int
    private var entries: [String: Entry] = [:]
    private var pending: [String] = []
    private var running = 0

    init(limit: Int) { self.limit = max(1, limit) }

    func value(for key: String, priority: Priority = .visible,
               _ work: @escaping @Sendable () async throws -> Value) async throws -> Value {
        let waiter = UUID()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                if var entry = entries[key] {
                    entry.waiters[waiter] = continuation
                    if priority.rawValue > entry.priority.rawValue { entry.priority = priority }
                    entries[key] = entry
                } else {
                    entries[key] = Entry(generation: UUID(), work: work, priority: priority,
                                         waiters: [waiter: continuation])
                    pending.append(key)
                }
                startAvailable()
            }
        } onCancel: {
            Task { await self.cancel(key: key, waiter: waiter) }
        }
    }

    private func cancel(key: String, waiter: UUID) {
        guard var entry = entries[key], let continuation = entry.waiters.removeValue(forKey: waiter) else { return }
        continuation.resume(throwing: CancellationError())
        if entry.waiters.isEmpty {
            entries.removeValue(forKey: key)
            pending.removeAll { $0 == key }
            // A replacement with this key gets a new generation. The old
            // completion cannot remove it or deliver a stale image to it.
            entry.task?.cancel()
        } else {
            entries[key] = entry
        }
        startAvailable()
    }

    private func startAvailable() {
        while running < limit, !pending.isEmpty {
            // A visible poster goes before queued speculative downloads.
            let index = pending.firstIndex { entries[$0]?.priority == .visible } ?? 0
            let key = pending.remove(at: index)
            guard var entry = entries[key] else { continue }
            let generation = entry.generation, work = entry.work
            running += 1
            entry.task = Task(priority: entry.priority == .visible ? .userInitiated : .utility) {
                let result: Result<Value, Error>
                do {
                    try Task.checkCancellation()
                    result = .success(try await work())
                } catch { result = .failure(error) }
                self.finished(key: key, generation: generation, result: result)
            }
            entries[key] = entry
        }
    }

    private func finished(key: String, generation: UUID, result: Result<Value, Error>) {
        running -= 1
        if let entry = entries[key], entry.generation == generation {
            entries.removeValue(forKey: key)
            for waiter in entry.waiters.values { waiter.resume(with: result) }
        }
        startAvailable()
    }

    /// Counts only, useful to assert real scheduling without exposing URLs.
    var activity: (running: Int, queued: Int, waiters: Int) {
        (running, pending.count, entries.values.reduce(0) { $0 + $1.waiters.count })
    }
}
