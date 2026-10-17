import SwiftUI

@MainActor
final class SearchViewModel: ObservableObject {
    @Published var query = ""
    @Published var results: [MetaItem] = []
    @Published var isSearching = false
    /// Shown while the query is empty — the tab opens onto something browseable
    /// (Apple TV style) instead of a bare "start typing" void. Loaded once.
    @Published var trending: [MetaItem] = []

    private var searchTask: Task<Void, Never>?
    private var loadedTrending = false
    private var completedQuery: String?
    private let requestLimit: Int
    private let debounce: Duration
    let includesAnime: Bool
    private let catalogLoader: @Sendable (InstalledAddon, ManifestCatalog, String) async throws -> [MetaItem]

    init(includesAnime: Bool = false, requestLimit: Int = AddonSweepLimits.catalogs,
         debounce: Duration = .milliseconds(350),
         catalogLoader: @escaping @Sendable (InstalledAddon, ManifestCatalog, String) async throws -> [MetaItem] = {
             try await StremioAPI.catalog(addon: $0, catalog: $1, search: $2)
         }) {
        self.requestLimit = max(1, requestLimit)
        self.includesAnime = includesAnime
        self.debounce = debounce
        self.catalogLoader = catalogLoader
    }

    func suspendSearch() {
        searchTask?.cancel()
        searchTask = nil
        isSearching = false
    }

    func resetForProfile() {
        suspendSearch()
        query = ""; results = []; trending = []
        loadedTrending = false; completedQuery = nil
    }

    func resumeSearchIfNeeded(addonManager: AddonManager) {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if trimmed.count >= 2, completedQuery != trimmed {
            search(addonManager: addonManager)
        }
    }

    func search(addonManager: AddonManager) {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else {
            results = []
            isSearching = false
            completedQuery = nil
            return
        }
        isSearching = true
        let targets = Self.searchTargets(addonManager).filter { includesAnime || !NTVAnimeDomain.contains($0.1) }
        let work = targets.map { ($0.0, $0.1, Self.limit(for: $0.0)) }
        let loader = catalogLoader, limit = requestLimit, delay = debounce
        searchTask = Task {
            do { try await Task.sleep(for: delay) } catch { return }
            guard !Task.isCancelled else { return }

            // Collect by target INDEX, not by completion. `for await` on a task
            // group yields in the order tasks finish, so the merged list was
            // ordered by whichever add-on answered fastest — a race. A slow
            // Cinemeta behind a fast torrent aggregator put junk on top, and
            // the same search could come back in a different order twice in a
            // row. Now the order is the one `searchTargets` decided.
            let batches = await boundedConcurrentMap(work, limit: limit) { target in
                let items = (try? await loader(target.0, target.1, trimmed)) ?? []
                return Array(items.prefix(target.2))
            }
            guard !Task.isCancelled else { return }

            var merged: [MetaItem] = []
            var seen = Set<String>()
            for items in batches {
                // Keyed on `id` alone: the grids' `ForEach` identify rows by
                // `MetaItem.id`, so "tt123" as `series` from one addon and
                // as `tv` from another must not both survive.
                for item in items where !seen.contains(item.id) {
                    guard includesAnime || !NTVAnimeLibrary.shared.contains(item) else { continue }
                    seen.insert(item.id)
                    merged.append(item)
                }
            }
            results = merged
            isSearching = false
            completedQuery = trimmed
        }
    }

    /// Most results one catalog may contribute to a search.
    private static let perCatalogLimit = 40
    /// A much tighter cap for stream-only source add-ons. Ranking them last
    /// stops them leading the results but not from filling the tail: four
    /// searchable catalogs at the normal cap is still 160 per-release rows
    /// behind the real titles. They keep a foothold rather than a flood.
    private static let sourceAddonLimit = 8

    private static func limit(for addon: InstalledAddon) -> Int {
        searchRank(addon) == 2 ? sourceAddonLimit : perCatalogLimit
    }

    /// Every searchable catalog, metadata add-ons first.
    ///
    /// Search is for finding TITLES. An add-on that provides `meta` describes
    /// titles; one that only provides `stream` is a source aggregator whose
    /// catalog lists individual releases. When such an add-on sat above
    /// Cinemeta in the list, search filled up with single torrents for random
    /// episodes and users had to reorder their add-ons by hand to get it back.
    /// Ordering by capability rather than by install position is that
    /// workaround, done automatically.
    ///
    /// Source add-ons are still searched, just last — excluding them outright
    /// would silently drop results from a legitimately configured add-on.
    static func searchTargets(_ addonManager: AddonManager) -> [(InstalledAddon, ManifestCatalog)] {
        addonManager.catalogAddons
            .enumerated()
            // `sorted` is not documented as stable, so the install index is an
            // explicit tiebreaker — without it, add-ons of equal rank could
            // reshuffle between searches.
            .sorted { a, b in
                let (ra, rb) = (Self.searchRank(a.element), Self.searchRank(b.element))
                return ra == rb ? a.offset < b.offset : ra < rb
            }
            .flatMap { entry in
                (entry.element.manifest.catalogs ?? [])
                    .filter { $0.supportsSearch }
                    .map { (entry.element, $0) }
            }
    }

    /// Lower sorts first: metadata providers, then anything else, then
    /// stream-only source add-ons.
    private static func searchRank(_ addon: InstalledAddon) -> Int {
        if addon.manifest.providesMeta { return 0 }
        if addon.manifest.providesStreams { return 2 }
        return 1
    }

    /// First extra-free catalog's top titles, fetched once per session.
    func loadTrendingIfNeeded(addonManager: AddonManager) async {
        guard !loadedTrending else { return }
        loadedTrending = true
        // Same ordering problem as search: "the first add-on with an
        // extra-free catalog" made a torrent aggregator's release listing the
        // Trending shelf whenever one happened to be installed above Cinemeta.
        let ranked = addonManager.catalogAddons
            .enumerated()
            .sorted { a, b in
                let (ra, rb) = (Self.searchRank(a.element), Self.searchRank(b.element))
                return ra == rb ? a.offset < b.offset : ra < rb
            }
            .map(\.element)
        for addon in ranked {
            guard !Task.isCancelled else { loadedTrending = false; return }
            guard let catalog = (addon.manifest.catalogs ?? []).first(where: { !$0.requiresExtra && NTVAnimeDomain.contains($0) == includesAnime })
            else { continue }
            if let items = try? await StremioAPI.catalog(addon: addon, catalog: catalog),
               !items.isEmpty {
                guard !Task.isCancelled else { loadedTrending = false; return }
                trending = Array(items.deduplicatedByID().filter { includesAnime || !NTVAnimeLibrary.shared.contains($0) }.prefix(18))
                return
            }
        }
    }
}

struct SearchView: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var posterLayout: HomeCatalogSettingsStore
    @EnvironmentObject private var addonManager: AddonManager
    // Owned by RootView so the query + results PERSIST across tab switches.
    // A local @StateObject would be rebuilt (and cleared) every time the Search
    // tab is re-entered.
    @ObservedObject var viewModel: SearchViewModel

    let onSelect: (MetaItem) -> Void
    var onOpenDiscover: () -> Void = {}
    var animeContext = false
    @FocusState private var searchFieldFocused: Bool

    private var usesNTVLayout: Bool { theme.palette.id == NTVDesign.palette.id }
    private var contentInset: CGFloat { usesNTVLayout ? NTVViewport.horizontalInset : OrivioSpacing.huge }

    private func posterWidth(in availableWidth: CGFloat?) -> CGFloat {
        guard let availableWidth, usesNTVLayout else { return posterLayout.posterSize.posterWidth }
        return NTVViewport.posterWidth(available: max(1, availableWidth - 2 * contentInset),
                                       preferred: posterLayout.posterSize.posterWidth)
    }

    var body: some View {
        Group {
            if usesNTVLayout {
                GeometryReader { geometry in searchContent(availableWidth: geometry.size.width) }
                    .ignoresSafeArea(edges: .horizontal)
            } else { searchContent(availableWidth: nil) }
        }
        .task {
            if viewModel.query.trimmingCharacters(in: .whitespaces).count >= 2 {
                viewModel.resumeSearchIfNeeded(addonManager: addonManager)
            } else {
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-ntvSearchLayoutFixture") {
                    viewModel.trending = (0..<18).map { MetaItem(id: "fixture.search.\($0)", type: "movie", name: "Film \($0 + 1)", releaseInfo: "2026") }
                    return
                }
                #endif
                await viewModel.loadTrendingIfNeeded(addonManager: addonManager)
            }
        }
        .onDisappear { viewModel.suspendSearch() }
        .onChange(of: viewModel.query) { _, _ in viewModel.search(addonManager: addonManager) }
    }

    private func searchContent(availableWidth: CGFloat?) -> some View {
        let profile = ProfileScopedDefaults.activeProfileID
        let results = viewModel.results.filter { animeContext || !NTVAnimeLibrary.shared.contains($0, profile: profile) }
        let trending = viewModel.trending.filter { animeContext || !NTVAnimeLibrary.shared.contains($0, profile: profile) }
        let movieResults = results.filter { !$0.isSeries }
        let showResults = results.filter(\.isSeries)
        return ZStack {
            ATVBackground()
            VStack(alignment: .leading, spacing: OrivioSpacing.lg) {
                if animeContext {
                    Text("Animés · Mes sources").font(.system(size: 38, weight: .semibold))
                        .padding(.horizontal, contentInset)
                        .accessibilityIdentifier("ntv.anime.sources.heading")
                }
                // Above the grid in z as well as in layout: the scroller below
                // is deliberately unclipped (see `scrollClipDisabled`), so a
                // row riding up used to draw straight over the field.
                searchBar
                    .zIndex(1)
                if viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    NTVRecentSearchRow(onFocusSearch: { searchFieldFocused = true }) { query in
                        searchFieldFocused = true
                        NTVRecentSearches.current.record(query)
                        viewModel.query = query
                    }
                    .padding(.horizontal, contentInset)
                }
                ScrollView(.vertical) {
                    if viewModel.isSearching && results.isEmpty {
                        OrivioLoadingView(label: "Recherche").frame(height: 480)
                    } else if !results.isEmpty {
                        // Results split by type: Movies on top, Shows below.
                        VStack(alignment: .leading, spacing: OrivioSpacing.xl) {
                            if !movieResults.isEmpty {
                                resultSection(title: animeContext ? "Films et résultats de mes addons" : "Films", items: movieResults, availableWidth: availableWidth)
                            }
                            if !showResults.isEmpty {
                                resultSection(title: animeContext ? "Séries et épisodes" : "Séries", items: showResults, availableWidth: availableWidth)
                            }
                        }
                        .padding(.top, OrivioSpacing.sm)
                        .padding(.bottom, OrivioSpacing.huge)
                    } else if viewModel.query.count >= 2 {
                        OrivioEmptyState(
                            icon: "magnifyingglass",
                            title: "Aucun résultat",
                            message: "Aucun résultat pour « \(viewModel.query) »."
                        )
                        .frame(height: 480)
                    } else if !trending.isEmpty {
                        // Idle: something to browse instead of an empty void.
                        resultSection(title: animeContext ? "Animés de mes sources" : "Tendances", items: trending, availableWidth: availableWidth)
                            .padding(.top, OrivioSpacing.sm)
                            .padding(.bottom, OrivioSpacing.huge)
                    } else {
                        OrivioEmptyState(
                            icon: "magnifyingglass",
                            title: "Commencer une recherche",
                            message: "Saisissez au moins deux caractères"
                        )
                        .frame(height: 480)
                    }
                }
                // Unclipped so a focused poster's platter and lift are not
                // sheared off at the left and right ends of the grid.
                .scrollClipDisabled()
                // …but that let rows travel straight up the page and over the
                // search field. This mask puts the ceiling back WITHOUT
                // restoring the side clipping: black (keep) everywhere the
                // scroller draws, extended far past its left, right and bottom
                // edges, and faded out across the top so a row scrolling away
                // dissolves just under the field instead of being cut. The
                // headroom above the fade is the focus lift of the first row,
                // which has to stay whole.
                .mask(alignment: .top) {
                    VStack(spacing: 0) {
                        LinearGradient(colors: [.clear, .black],
                                       startPoint: .top, endPoint: .bottom)
                            .frame(height: 34)
                        Color.black
                    }
                    .padding(.top, -18)
                    .padding(.horizontal, -600)
                    .padding(.bottom, -600)
                }
            }
            .padding(.top, OrivioSpacing.xl)
        }
    }

    private var searchBar: some View {
        HStack(spacing: OrivioSpacing.md) {
            SearchField(text: $viewModel.query,
                        focused: $searchFieldFocused,
                        placeholder: animeContext ? "Rechercher un animé dans mes addons" : "Rechercher un film ou une série",
                        onCommit: { NTVRecentSearches.current.record(viewModel.query) })
            if !animeContext {
                Button(action: onOpenDiscover) { SearchBarIcon(systemName: "square.grid.2x2") }
                    .buttonStyle(PlainCardButtonStyle())
            }
        }
        .padding(.horizontal, contentInset)
        .focusSection()
    }

    /// One titled grid section ("Movies" / "Shows" / "Trending"), its own focus
    /// section so up/down moves cleanly between the groups.
    private func resultSection(title: String, items: [MetaItem], availableWidth: CGFloat?) -> some View {
        let width = posterWidth(in: availableWidth)
        let columns = [GridItem(.adaptive(minimum: width, maximum: width),
                                spacing: usesNTVLayout ? NTVViewport.posterGap : OrivioSpacing.lg, alignment: .top)]
        return VStack(alignment: .leading, spacing: OrivioSpacing.md) {
            RowHeader(title: title)
                .padding(.leading, -OrivioSpacing.huge)   // RowHeader pads itself
            LazyVGrid(columns: columns, alignment: .leading, spacing: OrivioSpacing.xl) {
                ForEach(items) { item in
                    GridPosterCell(
                        item: item,
                        captionWidth: width,
                        onSelect: { item in
                            NTVRecentSearches.current.record(viewModel.query)
                            onSelect(item)
                        }
                    )
                    .accessibilityIdentifier("ntv.search.poster.\(item.type).\(item.id)")
                }
            }
        }
        .padding(.horizontal, contentInset)
        .focusSection()
    }
}


/// Round glass icon button in the Search top bar (opens Discover).
private struct SearchBarIcon: View {
    @EnvironmentObject private var theme: ThemeManager
    @Environment(\.isFocused) private var isFocused
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 26, weight: .semibold))
            .foregroundStyle(isFocused ? theme.palette.onSecondary : theme.palette.textPrimary)
            .frame(width: 74, height: 74)
            .background {
                if isFocused { Circle().fill(theme.palette.secondary) }
            }
            .liquidGlassIf(!isFocused, in: Circle())
            .overlay(Circle().strokeBorder(isFocused ? Color.white.opacity(0.95) : .clear, lineWidth: 3))
            .focusLift(OrivioFocus.card, isFocused)
            .animation(PerformanceSettingsStore.shared.buttonMotion(FusionMotion.focusEntry),
                       value: isFocused)
    }
}

/// The pill search field on glass. A plain `TextField` in a frosted resting
/// capsule; on focus tvOS draws its own light editing surface, and we DON'T add
/// a competing ring — otherwise the system fill sits inset inside our ring with
/// a dark gap between them (the "weird bar" the user saw). Letting the system
/// focus be the sole highlight means the highlight and the field are one shape.
private struct SearchField: View {
    @EnvironmentObject private var theme: ThemeManager
    @Binding var text: String
    @FocusState.Binding var focused: Bool
    var placeholder = "Rechercher un film ou une série"
    var onCommit: () -> Void = {}
    @State private var editing = false

    @ViewBuilder
    var body: some View {
        if theme.palette.id == NTVDesign.palette.id {
            Button { editing = true } label: {
                HStack(spacing: 16) {
                    Image(systemName: "magnifyingglass")
                    Text(text.isEmpty ? placeholder : text)
                        .foregroundStyle(text.isEmpty ? NTVDesign.textSecondary : NTVDesign.textPrimary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.system(size: 29, weight: .medium))
                .padding(.horizontal, 24)
                .frame(height: 74)
                .background { NTVGlassSurface(shape: Capsule(), clear: true) }
                .overlay { Capsule().strokeBorder(.white.opacity(focused ? 0.8 : 0.18), lineWidth: focused ? 2 : 1) }
            }
            .buttonStyle(PlainCardButtonStyle())
            .focused($focused)
            .accessibilityLabel(placeholder)
            .accessibilityValue(text)
            .accessibilityHint("Ouvrir la saisie et la dictée.")
            .accessibilityIdentifier("ntv.search.field")
            .fullScreenCover(isPresented: $editing, onDismiss: { focused = true }) {
                NTVSearchEntry(text: $text, placeholder: placeholder,
                               done: { onCommit(); editing = false }, cancel: { editing = false })
            }
        } else {
            legacyField
        }
    }

    private var legacyField: some View {
        HStack(spacing: OrivioSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(theme.palette.textTertiary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .focused($focused)
                .font(.system(size: 26))
                .foregroundStyle(theme.palette.textPrimary)
                .tint(theme.palette.secondary)
                .submitLabel(.search)
                .onSubmit(onCommit)
        }
        .padding(.horizontal, OrivioSpacing.xl)
        .frame(height: 74)
        .frame(maxWidth: .infinity)
        .background(Color.clear.liquidGlass(in: Capsule()))
        // No auto-focus: merely moving focus over the Search tab must not pop
        // the keyboard. Focus the field only when the user actually selects it.
    }
}

/// Keep the system keyboard, dictation and phone text entry. The browsing
/// surface remains glass; the native editor appears only after selection.
private struct NTVSearchEntry: View {
    @Binding var text: String
    var placeholder = "Film ou série"
    let done: () -> Void
    let cancel: () -> Void
    @FocusState private var editing: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            Text("Rechercher").font(.system(size: 38, weight: .semibold))
            TextField(placeholder, text: $text)
                .font(.system(size: 29))
                .foregroundStyle(editing ? .black : .white)
                .focused($editing)
                .submitLabel(.search)
                .onSubmit(done)
                .accessibilityIdentifier("ntv.search.editor")
            Button("Terminé", action: done)
                .buttonStyle(NTVActionButtonStyle())
                .accessibilityIdentifier("ntv.search.done")
        }
        .padding(60)
        .frame(maxWidth: 1120, maxHeight: .infinity, alignment: .center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(NTVDesign.background.ignoresSafeArea())
        .onAppear { editing = true }
        .onExitCommand(perform: cancel)
    }
}
