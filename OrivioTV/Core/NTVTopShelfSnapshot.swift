import Foundation

/// Local presentation data only. Stream URLs, addon URLs and credentials are
/// deliberately absent. Artwork is an already-cached JPEG in the shared area.
struct NTVTopShelfSnapshot: Codable {
    struct Entry: Codable {
        let id: String
        let type: String
        let title: String
        let subtitle: String?
        let imageFileName: String?
        let progress: Double?
    }
    let version: Int
    let writtenAt: Date
    let profileID: Int
    let entries: [Entry]
    static let maximumBytes = 128 * 1024

    static func decode(_ data: Data, now: Date = Date()) -> NTVTopShelfSnapshot? {
        guard data.count <= maximumBytes,
              let snapshot = try? JSONDecoder().decode(Self.self, from: data),
              snapshot.version == 1, snapshot.entries.count <= 10,
              now.timeIntervalSince(snapshot.writtenAt) >= -60,
              now.timeIntervalSince(snapshot.writtenAt) < 7 * 86400 else { return nil }
        return snapshot
    }

    static func safeArtworkName(_ name: String) -> Bool {
        name.range(of: "^topshelf-artwork-[a-f0-9]{64}\\.jpg$", options: .regularExpression) != nil
    }
}
