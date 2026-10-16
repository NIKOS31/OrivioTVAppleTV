import SwiftUI

/// Separate leaf: progress updates never invalidate the season/calendar tree.
struct NTVAnimeSavedLibrary: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var progress: ProgressStore
    @ObservedObject private var anime = NTVAnimeLibrary.shared
    let onSelect: (MetaItem) -> Void

    private struct Entry: Identifiable {
        let meta: MetaItem
        let progress: WatchProgress?
        var id: String { (meta.isSeries ? "series" : meta.type) + "|" + meta.id }
    }
    private var entries: [Entry] {
        let profile = ProfileScopedDefaults.activeProfileID
        let saved = library.sorted
        let savedByID = Dictionary(saved.map { (Entry(meta: $0.metaItem, progress: nil).id, $0.metaItem) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<String>()
        var result: [Entry] = []
        for row in progress.continueWatching(sortMode: .recentlyWatched) {
            let fallback = MetaItem(id: row.metaID, type: row.type, name: row.name,
                poster: row.poster, background: row.background, logo: row.logo)
            let meta = savedByID[Entry(meta: fallback, progress: nil).id] ?? fallback
            guard anime.contains(meta, profile: profile), seen.insert(Entry(meta: meta, progress: nil).id).inserted else { continue }
            result.append(Entry(meta: meta, progress: row))
        }
        for item in saved where anime.contains(item.metaItem, profile: profile) && seen.insert(Entry(meta: item.metaItem, progress: nil).id).inserted {
            result.append(Entry(meta: item.metaItem, progress: nil))
        }
        return result
    }

    var body: some View {
        let current = entries
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Text("Reprendre et retrouver mes animés").font(.system(size: 30, weight: .semibold))
                if current.isEmpty {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Ta liste commence ici").font(.system(size: 36, weight: .semibold))
                        Text("Ouvre un animé depuis cet espace et retrouve ici ta progression et tes favoris enregistrés dans nTV.")
                            .font(.system(size: 29)).foregroundStyle(NTVDesign.textSecondary)
                    }
                    .padding(36).frame(maxWidth: .infinity, alignment: .leading)
                    .background(NTVDesign.surface, in: RoundedRectangle(cornerRadius: 22))
                    .accessibilityIdentifier("ntv.anime.library.empty")
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 470), spacing: 28)], spacing: 28) {
                        ForEach(current) { entry in
                            Button { onSelect(entry.meta) } label: {
                                NTVAnimeSavedCard(meta: entry.meta, progress: entry.progress)
                            }
                            .buttonStyle(PlainCardButtonStyle())
                            .accessibilityLabel(entry.meta.name)
                            .accessibilityIdentifier("ntv.anime.saved.\(entry.id)")
                        }
                    }
                }
            }.padding(12)
        }.padding(.horizontal, -12).padding(.bottom, 48)
    }
}

private struct NTVAnimeSavedCard: View {
    @Environment(\.isFocused) private var focused
    let meta: MetaItem
    let progress: WatchProgress?
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Color.clear.aspectRatio(16.0 / 9.0, contentMode: .fit)
                .overlay { RemoteImage(url: progress?.episodeThumbnail ?? meta.background ?? meta.poster, maxDimension: 700) }
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(alignment: .bottom) {
                    if let progress {
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                Capsule().fill(.white.opacity(0.3))
                                Capsule().fill(.white).frame(width: geometry.size.width * CGFloat(progress.fraction))
                            }
                        }.frame(height: 5).padding(12)
                    }
                }
                .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(focused ? 0.9 : 0.1), lineWidth: focused ? 3 : 1) }
            Text(meta.name).font(.system(size: 29, weight: .semibold)).lineLimit(2)
                .frame(height: 70, alignment: .topLeading)
            Text(progress.map { row in
                if let season = row.season, let episode = row.episode { return "S\(season) · Épisode \(episode)" }
                return "Continuer la lecture"
            } ?? "Dans ma bibliothèque")
            .font(.system(size: 25)).foregroundStyle(NTVDesign.textSecondary)
        }
        .scaleEffect(focused ? 1.025 : 1)
    }
}
