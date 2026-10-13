import Foundation

enum NTVSourceAvailability: Sendable, Equatable {
    case available, absent, unknown
}

/// Only facts, in memory: no media URL, token, image or account data is saved.
/// One title at a time across all rows; shared consumers cancel independently.
actor NTVSourceAvailabilityStore {
    static let shared = NTVSourceAvailabilityStore()
    private let requests = NTVSharedWorkPool<NTVSourceAvailability>(limit: 1)
    private struct Record { let result: NTVSourceAvailability; let expires: Date }
    private var records: [String: Record] = [:]
    private var order: [String] = []

    func absentUntil(for items: [MetaItem], scope: String) -> [String: Date] {
        let now = Date()
        var result: [String: Date] = [:]
        for item in items {
            if let record = records[scope + "#" + item.type + "#" + item.id],
               record.result == .absent, record.expires > now { result[item.id] = record.expires }
        }
        return result
    }

    static func scope(profile: Int, addons: [InstalledAddon]) -> String {
        ImageCache.artworkKey(String(profile) + "#" + addons.map { $0.manifestURL }.sorted().joined(separator: "#"), budget: nil)
    }

    func check(item: MetaItem, sources: [InstalledAddon], metadata: [InstalledAddon] = [], scope: String,
               load: @escaping @Sendable (InstalledAddon, String, String) async throws -> [Stream] = {
                   try await StremioAPI.streamsForAvailability(addon: $0, type: $1, id: $2)
               }) async throws -> NTVSourceAvailability {
        try Task.checkCancellation()
        let key = scope + "#" + item.type + "#" + item.id
        if let record = records[key], record.expires > Date() { return record.result }
        let result = try await requests.value(for: key) {
            var candidate = item
            if item.isSeries && item.videos == nil,
               let provider = metadata.first(where: { $0.enabled && $0.handles(id: item.id) }) {
                do {
                    let full = try await StremioAPI.meta(addon: provider, type: item.type, id: item.id)
                    try Task.checkCancellation()
                    if full.id == item.id, full.type == item.type { candidate = full }
                } catch { try Task.checkCancellation() }
            }
            return try await Self.probe(item: candidate, sources: sources, load: load)
        }
        try Task.checkCancellation()
        if records[key] == nil { order.append(key) }
        records[key] = Record(result: result, expires: Date().addingTimeInterval(result == .available ? 300 : 30))
        while order.count > 512 { records.removeValue(forKey: order.removeFirst()) }
        return result
    }

    private static func probe(item: MetaItem, sources: [InstalledAddon],
                              load: @escaping @Sendable (InstalledAddon, String, String) async throws -> [Stream]) async throws -> NTVSourceAvailability {
        let addons = sources.filter { $0.enabled && $0.handles(id: item.id) && ($0.manifest.types?.contains(item.type) ?? true) }
        guard !addons.isEmpty else { return .unknown }
        var ids = [item.id]
        var canProveAbsence = true
        if item.isSeries {
            // Never infer that an entire series is absent from one empty episode.
            // Catalogs without episode metadata remain unknown until a full
            // metadata item is available; a long series is only sampled for positives.
            let released = (item.videos ?? []).filter {
                ($0.airedDate.map { $0 <= Date() } ?? true) && ($0.season ?? 0) > 0
            }
            guard !released.isEmpty else { return .unknown }
            ids = Array(released.prefix(3)).map(\.id)
            canProveAbsence = released.count <= ids.count && released.count == item.videos?.count
        }
        var uncertain = !canProveAbsence
        for id in ids {
            try Task.checkCancellation()
            for addon in addons {
                try Task.checkCancellation()
                do {
                    let streams = try await load(addon, item.type, id)
                    try Task.checkCancellation()
                    if streams.contains(where: { stream in
                        guard let raw = stream.url, let url = URL(string: raw),
                              let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
                              url.host?.isEmpty == false else { return false }
                        return true
                    }) { return .available }
                    // Error placeholders, torrents and external-only entries
                    // cannot prove a playable title is absent.
                    if !streams.isEmpty { uncertain = true }
                } catch is CancellationError { throw CancellationError() }
                catch { uncertain = true }
            }
        }
        return uncertain ? .unknown : .absent
    }
}
