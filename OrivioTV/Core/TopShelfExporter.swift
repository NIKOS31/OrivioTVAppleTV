import Foundation
import TVServices
import CryptoKit

/// Writes the Continue Watching list into the shared app-group container so
/// the Top Shelf extension can render it on the tvOS home screen. Called from
/// ProgressStore whenever progress persists — the snapshot is tiny (≤10
/// entries) and written off-main alongside the progress save itself.
///
/// Sideload caveat: if the signing tool strips the app-group entitlement,
/// `containerURL` is nil and this is a silent no-op — the app works, the
/// shelf falls back to the independent nTV brand image.
enum TopShelfExporter {
    /// App-only input. Private artwork origins are removed when exporting the
    /// shared NTVTopShelfSnapshot; the extension never receives these URLs.
    struct Entry: Codable {
        let id: String
        let type: String
        let title: String
        let subtitle: String?
        let imageURL: String?
        /// How far in, 0...1 — drawn as the bar across the bottom of the card.
        /// Optional so a snapshot written by an older build still decodes; it
        /// reads back as nil and the card simply has no bar.
        var progress: Double? = nil
    }

    /// Build the export entries on the caller's (main) side — cheap — so the
    /// disk write can happen on a background task with plain value data.
    static func entries(from progresses: [WatchProgress]) -> [Entry] {
        progresses.prefix(10).map { p in
            var subtitle: String?
            if let s = p.season, let e = p.episode {
                subtitle = "S\(s):E\(e)"
                if let t = p.episodeTitle, !t.isEmpty { subtitle! += " · \(t)" }
            }
            return Entry(
                id: p.metaID,
                type: p.type,
                title: p.name,
                subtitle: subtitle,
                // The system continuation section uses portrait posters.
                imageURL: p.poster ?? p.background ?? p.episodeThumbnail,
                // `fraction` is already position/duration guarded against a
                // zero duration; clamp anyway because playbackProgress is
                // documented as 0...1 and a row restored from another device
                // can carry a position past its duration.
                progress: min(max(p.fraction, 0), 1)
            )
        }
    }

    /// Whether the profile whose data would be exported is PIN-locked.
    ///
    /// The Top Shelf draws on the tvOS home screen — OUTSIDE the app, before
    /// the "Who's watching?" gate ever appears. Exporting a locked profile's
    /// Continue Watching would put the titles, episode names and artwork that
    /// the PIN exists to hide in front of anyone who walks up to the TV, with
    /// no PIN asked for. Read straight from the profile blob rather than
    /// taking a ProfileStore dependency: this runs on the persist path, off
    /// the main actor, where the store isn't reachable.
    fileprivate static var profileScope: (id: Int, locked: Bool) {
        struct Row: Decodable { let id: Int; let pinEnabled: Bool? }
        let defaults = UserDefaults.standard
        let active = defaults.object(forKey: "orivio.profiles.active") as? Int ?? 1
        guard let data = defaults.data(forKey: "orivio.profiles.v1"),
              let rows = try? JSONDecoder().decode([Row].self, from: data)
        else { return (active, true) }
        guard let row = rows.first(where: { $0.id == active }) else { return (active, true) }
        return (active, row.pinEnabled ?? false)
    }

    /// Monotonic ticket for shelf writes, taken on the main actor at each
    /// call site so the ORDER the app decided on is the order the file sees.
    /// Three writers used to race unordered (the periodic persister, the
    /// profile-switch reload and the PIN refresh), and a profile switch could
    /// have the previous profile's queued write land last — its titles on the
    /// home screen under the new profile.
    @MainActor private static var sequence: UInt64 = 0
    @MainActor static func nextSequence() -> UInt64 {
        sequence += 1
        return sequence
    }

    /// Ordered write: a ticket older than the last one written is dropped.
    static func writeOrdered(_ entries: [Entry], sequence: UInt64, force: Bool = false) async {
        await TopShelfWriter.shared.write(entries, sequence: sequence, force: force)
    }

}

/// Serialises Top Shelf snapshot writes and enforces their ticket order.
private actor TopShelfWriter {
    static let shared = TopShelfWriter()
    private var lastSequence: UInt64 = 0
    private var fingerprint: String?
    private var lastPublish = Date.distantPast

    func write(_ entries: [TopShelfExporter.Entry], sequence: UInt64, force: Bool) async {
        guard sequence > lastSequence else { return }
        lastSequence = sequence
        // No authorized shared container: retain the independent brand shelf.
        // No extra request or signing/account operation is attempted here.
        guard let file = AppGroupResolver.sharedFile("topshelf.json") else { return }
        let scope = TopShelfExporter.profileScope
        let input = scope.locked ? [] : Array(entries.prefix(10))
        let identity = String(scope.id) + "#" + input.map { "\($0.type)#\($0.id)#\($0.title)#\($0.subtitle ?? "")#\($0.imageURL ?? "")" }.joined(separator: "|")
        let nextFingerprint = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
        guard force || fingerprint != nextFingerprint || Date().timeIntervalSince(lastPublish) >= 20 else { return }
        let directory = file.deletingLastPathComponent()
        var exported: [NTVTopShelfSnapshot.Entry] = []
        for entry in input {
            var imageFileName: String?
            if let source = entry.imageURL {
                let hash = SHA256.hash(data: Data((entry.id + "#" + source).utf8)).map { String(format: "%02x", $0) }.joined()
                let name = "topshelf-artwork-\(hash).jpg"
                let destination = directory.appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: destination.path) { imageFileName = name }
                else if let image = await ImageCache.shared.diskImage(for: source, budget: 600),
                        let data = image.jpegData(compressionQuality: 0.82), data.count <= 1024 * 1024 {
                    try? data.write(to: destination, options: .atomic)
                    if FileManager.default.fileExists(atPath: destination.path) { imageFileName = name }
                }
                // Reuse decoded/disk artwork only. Top Shelf adds no network
                // requests while the app navigates or plays a film.
            }
            exported.append(.init(id: entry.id, type: entry.type, title: String(entry.title.prefix(160)),
                subtitle: entry.subtitle.map { String($0.prefix(80)) }, imageFileName: imageFileName,
                progress: entry.progress.flatMap { $0.isFinite ? min(max($0, 0), 1) : nil }))
        }
        let current = TopShelfExporter.profileScope
        guard sequence == lastSequence, current.id == scope.id, current.locked == scope.locked else { return }
        let snapshot = NTVTopShelfSnapshot(version: 1, writtenAt: Date(), profileID: scope.id, entries: exported)
        guard let data = try? JSONEncoder().encode(snapshot), data.count <= NTVTopShelfSnapshot.maximumBytes else { return }
        do { try data.write(to: file, options: .atomic) } catch { return }
        fingerprint = nextFingerprint; lastPublish = Date()
        let retained = Set(exported.compactMap(\.imageFileName))
        if let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            for old in files where NTVTopShelfSnapshot.safeArtworkName(old.lastPathComponent) && !retained.contains(old.lastPathComponent) {
                try? FileManager.default.removeItem(at: old)
            }
        }
        TVTopShelfContentProvider.topShelfContentDidChange()
    }
}
