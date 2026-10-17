import SwiftUI

@MainActor
final class CatalogSeeAllViewModel: ObservableObject {
    @Published var items: [MetaItem] = []
    @Published var isLoading = false
    @Published var reachedEnd = false
    @Published private(set) var failed = false
    @Published private(set) var needsPageAdvance = false

    let addon: InstalledAddon
    let catalog: ManifestCatalog
    private var seenIDs = Set<String>()
    private var consumedItems = 0
    private let fetch: (Int) async throws -> [MetaItem]

    init(addon: InstalledAddon, catalog: ManifestCatalog, fetch: ((Int) async throws -> [MetaItem])? = nil) {
        self.addon = addon
        self.catalog = catalog
        self.fetch = fetch ?? { try await StremioAPI.catalog(addon: addon, catalog: catalog, skip: $0) }
    }

    /// Load the next page. Stremio paginates via `skip`; we advance by however
    /// many provider items were consumed, including hidden anime. A filtered
    /// page must not be fetched forever from the same visible-item offset.
    func loadMore() async {
        guard !isLoading, !reachedEnd else { return }
        isLoading = true
        defer { isLoading = false }
        // An error is NOT the end of the catalog. `try?` folded a timeout into
        // an empty page and `reachedEnd` latched: one blip on the FIRST page
        // showed "no titles" for a full catalog with no way to retry, and one
        // mid-scroll ended infinite scroll for the visit. A failed page just
        // leaves the trigger cell in place to try again.
        let page: [MetaItem]
        do { page = try await fetch(consumedItems) }
        catch { failed = true; return }
        failed = false
        let fresh = page.filter { seenIDs.insert($0.id).inserted }
        consumedItems += page.count
        if fresh.isEmpty {
            reachedEnd = true
            needsPageAdvance = false
        } else {
            let profile = ProfileScopedDefaults.activeProfileID
            let visible = fresh.filter { !NTVAnimeLibrary.shared.contains($0, profile: profile) }
            items.append(contentsOf: visible)
            needsPageAdvance = visible.isEmpty
        }
    }
}

/// A full, paginated grid for a single catalog — the "See All" destination from
/// a home row. Mirrors Android's `CatalogSeeAllScreen`.
struct CatalogSeeAllView: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var posterLayout: HomeCatalogSettingsStore
    @StateObject private var viewModel: CatalogSeeAllViewModel

    let title: String
    let onSelect: (MetaItem) -> Void

    /// Bound to the poster-size setting, like Home, Search, Library and
    /// Discover. A hardcoded 220pt column clipped: `PosterCard` draws at the
    /// user's chosen 180/220/264, so at Large the card was 44pt wider than its
    /// column and neighbouring cards overlapped, while at Small it left 40pt of
    /// dead gutter.
    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: posterLayout.posterSize.posterWidth,
                            maximum: posterLayout.posterSize.posterWidth),
                  spacing: OrivioSpacing.lg, alignment: .top)]
    }

    init(addon: InstalledAddon, catalog: ManifestCatalog, title: String, onSelect: @escaping (MetaItem) -> Void) {
        _viewModel = StateObject(wrappedValue: CatalogSeeAllViewModel(addon: addon, catalog: catalog))
        self.title = title
        self.onSelect = onSelect
    }

    var body: some View {
        ZStack {
            ATVBackground()
            if viewModel.items.isEmpty && viewModel.isLoading {
                OrivioLoadingView(label: "Chargement de \(title)", holdsFocus: true)
            } else if viewModel.items.isEmpty {
                VStack(spacing: 24) {
                    Text(title).font(.system(size: 38, weight: .semibold))
                    Text(viewModel.failed ? "Le catalogue n’a pas pu être chargé." : viewModel.reachedEnd ? "Aucun autre titre dans ce catalogue." : "Les animés de cette page sont disponibles dans l’espace Animés.")
                        .font(.system(size: 29)).foregroundStyle(theme.palette.textSecondary)
                    if !viewModel.reachedEnd {
                        Button(viewModel.failed ? "Réessayer" : "Continuer dans ce catalogue") { Task { await viewModel.loadMore() } }
                            .buttonStyle(NTVActionButtonStyle())
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: OrivioSpacing.xl) {
                        Text(title)
                            .font(.system(size: 52, weight: .heavy))
                            .foregroundStyle(theme.palette.textPrimary)
                            .padding(.leading, OrivioSpacing.huge)
                            .padding(.top, OrivioSpacing.xxl)

                        LazyVGrid(columns: columns, alignment: .leading, spacing: OrivioSpacing.xl) {
                            ForEach(viewModel.items) { item in
                                Button {
                                    onSelect(item)
                                } label: {
                                    PosterCard(item: item)
                                }
                                .mediaCardButtonStyle()
                                .onAppear {
                                    // Prefetch the next page as the tail comes into view.
                                    if item.id == viewModel.items.last?.id {
                                        Task { await viewModel.loadMore() }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, OrivioSpacing.huge)

                        if viewModel.isLoading {
                            ProgressView().tint(theme.palette.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.bottom, OrivioSpacing.huge)
                        } else if !viewModel.reachedEnd && (viewModel.needsPageAdvance || viewModel.failed) {
                            Button(viewModel.failed ? "Réessayer" : "Charger la suite") { Task { await viewModel.loadMore() } }
                                .buttonStyle(NTVActionButtonStyle())
                                .padding(.horizontal, OrivioSpacing.huge)
                        }
                    }
                    .padding(.bottom, OrivioSpacing.huge)
                }
                .scrollClipDisabled()
            }
        }
        .task { if viewModel.items.isEmpty { await viewModel.loadMore() } }
    }
}
