import SwiftUI

/// History changes invalidate this small leaf, not the search result grids.
struct NTVRecentSearchRow: View {
    @EnvironmentObject private var profiles: ProfileStore
    @ObservedObject private var history = NTVRecentSearches.current
    var onFocusSearch: () -> Void = {}
    let onSelect: (String) -> Void

    var body: some View {
        let profile = profiles.activeProfileID
        let queries = history.queries(profile: profile)
        if !queries.isEmpty {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 28) {
                    Text("Recherches récentes").font(.system(size: 29, weight: .semibold))
                    Spacer()
                    Button("Tout effacer") {
                        onFocusSearch()
                        history.clear(profile: profile)
                    }
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
                                    if history.queries(profile: profile).isEmpty { onFocusSearch() }
                                }
                            }
                        }
                    }.padding(8)
                }
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
                // A horizontal ScrollView otherwise takes all remaining
                // height from Search's VStack and squeezes out the posters.
                .frame(height: 98)
            }
            .focusSection()
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("ntv.search.recent")
        }
    }
}
