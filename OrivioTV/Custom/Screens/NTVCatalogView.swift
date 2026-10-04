import SwiftUI

/// A native root destination using the upstream generic catalog loader and
/// poster cells. No provider names, catalog IDs or genres are hardcoded.
struct NTVCatalogView: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var settings: HomeCatalogSettingsStore
    @EnvironmentObject private var addons: AddonManager
    @ObservedObject var viewModel: DiscoverViewModel
    let mediaType: String
    let title: String
    let onSelect: (MetaItem) -> Void
    let onPlayManually: (MetaItem, MetaVideo?) -> Void
    let onBackAtRoot: () -> Void
    let onOpenSettings: () -> Void

    @State private var catalogID = ""
    @State private var genre = ""
    @FocusState private var focusedID: String?

    private struct Catalog: Identifiable {
        let addon: InstalledAddon
        let manifest: ManifestCatalog
        var id: String { "\(addon.id)#\(manifest.type)#\(manifest.id)" }
        var name: String { manifest.name ?? manifest.id.capitalized }
    }

    private var catalogs: [Catalog] {
        addons.catalogAddons.flatMap { addon in
            (addon.manifest.catalogs ?? [])
                .filter { $0.type == mediaType && !$0.requiresExtra }
                .map { Catalog(addon: addon, manifest: $0) }
        }
    }

    var body: some View {
        let catalogs = self.catalogs
        let selected = catalogs.first { $0.id == catalogID } ?? catalogs.first
        let genres = selected?.manifest.genreOptions ?? []
        let activeGenre = genres.contains(genre) ? genre : ""
        ZStack {
            ATVBackground()
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 30) {
                        Text(title)
                            .font(.system(size: 38, weight: .semibold))
                            .foregroundStyle(theme.palette.textPrimary)
                            .accessibilityIdentifier("ntv.catalog.\(mediaType).heading")

                        HStack(spacing: 24) {
                            if catalogs.count > 1 {
                                OrivioDropdown(title: "Catalogue", selection: selected?.id ?? "",
                                    options: catalogs.map { OrivioDropdownOption($0.id, $0.name) },
                                    triggerWidth: 500) {
                                        catalogID = $0
                                        genre = ""
                                    }
                            } else if let selected {
                                Text(selected.name)
                                    .font(.system(size: 26, weight: .medium))
                                    .foregroundStyle(theme.palette.textSecondary)
                            }
                            if !genres.isEmpty {
                                OrivioDropdown(title: "Genre", selection: activeGenre,
                                    options: [OrivioDropdownOption("", "Tous les genres")]
                                        + genres.map { OrivioDropdownOption($0) },
                                    triggerWidth: 380) { genre = $0 }
                            }
                            Spacer(minLength: 0)
                        }
                        .focusSection()

                        if selected == nil {
                            NTVEmptyCatalog(
                                message: "Aucun catalogue de \(title.lowercased()) disponible. Activez ou ajoutez un addon dans les réglages.",
                                onOpenSettings: onOpenSettings)
                        } else if viewModel.items.isEmpty && viewModel.isLoading {
                            OrivioLoadingView(label: "Chargement des catalogues").frame(height: 360)
                        } else if viewModel.items.isEmpty {
                            NTVEmptyCatalog(
                                message: "Aucun titre chargé pour cette sélection.",
                                onOpenSettings: onOpenSettings,
                                onRetry: {
                                    if let selected {
                                        Task { await viewModel.reset(addon: selected.addon,
                                            catalog: selected.manifest,
                                            genre: activeGenre.isEmpty ? nil : activeGenre) }
                                    }
                                })
                        } else {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: settings.posterSize.posterWidth,
                                maximum: settings.posterSize.posterWidth), spacing: 28, alignment: .top)],
                                alignment: .leading, spacing: 36) {
                                ForEach(viewModel.items) { item in
                                    GridPosterCell(item: item,
                                        captionWidth: settings.posterSize.posterWidth,
                                        onSelect: onSelect, onPlayManually: onPlayManually,
                                        gridFocus: $focusedID)
                                        .id(item.id)
                                        .onAppear {
                                            if item.id == viewModel.items.last?.id {
                                                Task { await viewModel.loadMore() }
                                            }
                                        }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, OrivioSpacing.huge)
                    .padding(.top, OrivioSpacing.xl)
                    .padding(.bottom, 120)
                }
                .scrollClipDisabled()
                .onExitCommand { backToTop(proxy) }
            }
        }
        .task(id: "\(selected?.id ?? "")#\(activeGenre)") {
            if let selected {
                await viewModel.reset(addon: selected.addon, catalog: selected.manifest,
                                      genre: activeGenre.isEmpty ? nil : activeGenre)
            }
        }
    }

    private func backToTop(_ proxy: ScrollViewProxy) {
        guard let first = viewModel.items.first?.id, let focused = focusedID, focused != first else {
            onBackAtRoot()
            return
        }
        withAnimation(FusionMotion.focusMove) { proxy.scrollTo(first, anchor: .top) }
        DispatchQueue.main.async { focusedID = first }
    }
}
