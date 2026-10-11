import Foundation
import TVServices

/// Writes the Continue Watching list into the shared app-group container so
/// the Top Shelf extension can render it on the tvOS home screen. Called from
/// ProgressStore whenever progress persists — the snapshot is tiny (≤10
/// entries) and written off-main alongside the progress save itself.
///
/// Sideload caveat: if the signing tool strips the app-group entitlement,
/// `containerURL` is nil and this is a silent no-op — the app works, the
/// shelf just stays empty.
enum TopShelfExporter {
    /// Mirrored by TopShelfProvider.Entry in the extension target — keep the
    /// fields/keys in sync.
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
                // Wide art to match the .hdtv shape: episode still, then
                // backdrop, then poster as a last resort.
                imageURL: p.episodeThumbnail ?? p.background ?? p.poster,
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
    private static var activeProfileIsLocked: Bool {
        struct Row: Decodable { let id: Int; let pinEnabled: Bool? }
        let defaults = UserDefaults.standard
        let active = defaults.object(forKey: "orivio.profiles.active") as? Int ?? 1
        guard let data = defaults.data(forKey: "orivio.profiles.v1"),
              let rows = try? JSONDecoder().decode([Row].self, from: data)
        else { return false }
        return rows.first { $0.id == active }?.pinEnabled ?? false
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
    static func writeOrdered(_ entries: [Entry], sequence: UInt64) async {
        await TopShelfWriter.shared.write(entries, sequence: sequence)
    }

    /// Branding uses no viewing history or remote URLs. Remove the obsolete
    /// snapshot once; repeated progress saves need no Top Shelf disk writes.
    static func write(_ entries: [Entry]) {
        for name in ["topshelf.json", "topshelf-scheme.txt"] {
            if let file = AppGroupResolver.sharedFile(name) { try? FileManager.default.removeItem(at: file) }
        }
        TVTopShelfContentProvider.topShelfContentDidChange()
    }

}

/// Serialises Top Shelf snapshot writes and enforces their ticket order.
private actor TopShelfWriter {
    static let shared = TopShelfWriter()
    private var lastSequence: UInt64 = 0

    func write(_ entries: [TopShelfExporter.Entry], sequence: UInt64) {
        guard lastSequence == 0 else { return }
        lastSequence = sequence
        TopShelfExporter.write(entries)
    }
}
