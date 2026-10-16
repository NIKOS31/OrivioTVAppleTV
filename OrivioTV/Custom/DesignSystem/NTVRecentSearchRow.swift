import SwiftUI

/// History changes invalidate this small leaf, not the search result grids.
struct NTVRecentSearchRow: View {
    @EnvironmentObject private var profiles: ProfileStore
    @ObservedObject private var history = NTVRecentSearches.shared
    let onSelect: (String) -> Void

    var body: some View {
        let profile = profiles.activeProfileID
        let queries = history.queries(profile: profile)
        if !queries.isEmpty {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 28) {
                    Text("Recherches récentes").font(.system(size: 29, weight: .semibold))
                    Spacer()
                    Button("Tout effacer") { history.clear(profile: profile) }
                        .buttonStyle(NTVActionButtonStyle())
                        .accessibilityIdentifier("ntv.search.recent.clear")
                }
                ScrollView(.horizontal) {
                    HStack(spacing: 20) {
                        ForEach(queries, id: \.self) { query in
                            Button { onSelect(query) } label: {
                                Label(query, systemImage: "clock.arrow.circlepath")
                                    .lineLimit(1).frame(maxWidth: 320)
                            }
                            .buttonStyle(NTVActionButtonStyle())
                            .accessibilityLabel("Rechercher à nouveau : \(query)")
                            .accessibilityHint("Appui prolongé pour supprimer cette recherche.")
                            .contextMenu {
                                Button("Supprimer cette recherche", role: .destructive) {
                                    history.remove(query, profile: profile)
                                }
                            }
                        }
                    }.padding(8)
                }
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
            }
            .focusSection()
            .accessibilityIdentifier("ntv.search.recent")
        }
    }
}
