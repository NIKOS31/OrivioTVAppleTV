import SwiftUI

struct NTVCatalogSource: Identifiable {
    let addon: InstalledAddon
    let catalog: ManifestCatalog
    var id: String { ImageCache.artworkKey("\(addon.id)#\(catalog.type)#\(catalog.id)", budget: nil) }
    var title: String { NTVFrench.catalogTitle(catalog.name ?? catalog.id.capitalized) }
}

/// Only visible shelves load. Focus stays inside a row and cannot republish
/// the browser or enumerate every installed manifest on each remote movement.
@MainActor final class NTVCatalogShelfModel: ObservableObject {
    static let previews = 24
    private static let requests = NTVSharedWorkPool<[MetaItem]>(limit: 3)
    @Published private(set) var items: [MetaItem] = []
    @Published private(set) var loading = false
    @Published private(set) var failed = false
    private var loadedAt: Date?
    let source: NTVCatalogSource
    let scope: String
    private let fetch: @Sendable (NTVCatalogSource) async throws -> [MetaItem]
    init(source: NTVCatalogSource, scope: String,
         fetch: @escaping @Sendable (NTVCatalogSource) async throws -> [MetaItem] = {
             try await StremioAPI.catalog(addon: $0.addon, catalog: $0.catalog)
         }) { self.source = source; self.scope = scope; self.fetch = fetch }
    func load() async {
        guard !loading, loadedAt.map({ Date().timeIntervalSince($0) < 300 }) != true else { return }
        loading = true
        defer { loading = false }
        do {
            let source = self.source
            let fetch = self.fetch
            let page = try await Self.requests.value(for: "\(scope)#\(source.id)") {
                try await fetch(source)
            }
            try Task.checkCancellation()
            var seen = Set<String>()
            // A lazy filter must be pure: Collection can evaluate its predicate
            // repeatedly while finding indices. Mutating `seen` inside it made
            // its bounds inconsistent and crashed both live rows and tests.
            var preview: [MetaItem] = []
            preview.reserveCapacity(Self.previews)
            for item in page where seen.insert(item.id).inserted {
                preview.append(item)
                if preview.count == Self.previews { break }
            }
            items = preview
            loadedAt = Date(); failed = false
        } catch is CancellationError {} catch { failed = true }
    }
}

@MainActor final class NTVCatalogBrowserModel: ObservableObject {
    @Published private(set) var sources: [NTVCatalogSource] = []
    private var fingerprint = ""
    private var shelves: [String: NTVCatalogShelfModel] = [:]
    private var order: [String] = []
    func configure(addons: [InstalledAddon], type: String, scope: String) {
        let available = addons.flatMap { addon in
            (addon.manifest.catalogs ?? []).filter { $0.type == type && !$0.requiresExtra }
                .map { NTVCatalogSource(addon: addon, catalog: $0) }
        }
        let next = scope + "#" + available.map { "\($0.id)#\($0.catalog.hashValue)" }.joined(separator: "#")
        guard next != fingerprint else { return }
        fingerprint = next; shelves = [:]; order = []
        var seen = Set<String>()
        sources = available.filter { seen.insert($0.id).inserted }
    }
    func shelf(_ source: NTVCatalogSource) -> NTVCatalogShelfModel {
        if let cached = shelves[source.id] { return cached }
        let value = NTVCatalogShelfModel(source: source, scope: fingerprint)
        shelves[source.id] = value; order.append(source.id)
        while order.count > 24 { shelves.removeValue(forKey: order.removeFirst()) }
        return value
    }
}

struct NTVCatalogView: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var addons: AddonManager
    @EnvironmentObject private var profiles: ProfileStore
    @ObservedObject var viewModel: NTVCatalogBrowserModel
    let mediaType: String
    let title: String
    let onSelect: (MetaItem) -> Void
    let onPlayManually: (MetaItem, MetaVideo?) -> Void
    let onSeeAll: (InstalledAddon, ManifestCatalog, String) -> Void
    let onBackAtRoot: () -> Void
    let onOpenSettings: () -> Void
    @State private var hero = HeroFocus()
    @State private var categoriesOpen = false
    @State private var requestedCategory: String?
    @FocusState private var categoryFocus: String?
    private var loadKey: String {
        String(profiles.activeProfileID) + "#" + addons.catalogAddons.map { "\($0.id)#\($0.manifest.catalogs?.hashValue ?? 0)" }.joined(separator: "#")
    }
    var body: some View {
        ZStack(alignment: .leading) {
            NTVFocusBackdrop(hero: hero, identifier: "ntv.catalog.\(mediaType).backdrop")
            ScrollViewReader { proxy in
                ZStack(alignment: .leading) {
                    ScrollView(.vertical) {
                        LazyVStack(alignment: .leading, spacing: 22) {
                            HStack {
                                Text(title).font(.system(size: 38, weight: .semibold))
                                    .ntvHalloweenDecor(.heading)
                                    .accessibilityIdentifier("ntv.catalog.\(mediaType).heading")
                                Spacer()
                                Button { categoriesOpen = true } label: { Label("Catégories", systemImage: "line.3.horizontal.decrease") }
                                    .buttonStyle(NTVActionButtonStyle())
                                    .accessibilityIdentifier("ntv.catalog.\(mediaType).categories")
                            }.padding(.horizontal, NTVViewport.horizontalInset)
                            NTVCatalogSpotlight(hero: hero)
                                .frame(height: 230, alignment: .topLeading)
                                .transaction { $0.animation = nil }
                                .padding(.horizontal, NTVViewport.horizontalInset)
                            if viewModel.sources.isEmpty {
                                NTVEmptyCatalog(message: "Ajoutez un addon proposant des catalogues de \(title.lowercased()).", onOpenSettings: onOpenSettings)
                                    .padding(.horizontal, NTVViewport.horizontalInset)
                            }
                            ForEach(viewModel.sources) { source in
                                NTVCatalogShelf(model: viewModel.shelf(source), hero: hero,
                                    onSelect: onSelect, onPlayManually: onPlayManually,
                                    onSeeAll: onSeeAll, onBackAtRoot: onBackAtRoot,
                                    focusRequested: requestedCategory == source.id)
                                    .id(source.id)
                            }
                        }.padding(.top, 26).padding(.bottom, 100)
                    }
                    .scrollClipDisabled().disabled(categoriesOpen)
                    if categoriesOpen {
                        categoryPanel(proxy).padding(.leading, NTVViewport.horizontalInset).padding(.vertical, 20)
                    }
                }
            }
        }
        .foregroundStyle(theme.palette.textPrimary)
        .ignoresSafeArea(edges: .horizontal)
        .toolbar(.hidden, for: .navigationBar)
        .onExitCommand {
            if categoriesOpen { closeCategories() } else { onBackAtRoot() }
        }
        .task(id: loadKey) {
            hero.layout = .pinnedFocus
            viewModel.configure(addons: addons.catalogAddons, type: mediaType, scope: String(profiles.activeProfileID))
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-ntvCatalogCategoriesDemo") { categoriesOpen = true }
            #endif
            if let first = viewModel.sources.first {
                let shelf = viewModel.shelf(first)
                await shelf.load()
                guard !Task.isCancelled else { return }
                if hero.item == nil, let item = shelf.items.first { hero.focus(item) }
            }
        }
        .onChange(of: profiles.activeProfileID) { _, _ in hero.item = nil }
        .onChange(of: categoriesOpen) { _, open in
            if open { categoryFocus = viewModel.sources.first?.id }
        }
    }
    private func categoryPanel(_ proxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Text("Catégories").font(.system(size: 30, weight: .semibold))
                Spacer()
                Button { closeCategories() } label: { Image(systemName: "xmark") }
                    .buttonStyle(NTVActionButtonStyle()).accessibilityLabel("Fermer les catégories")
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(viewModel.sources) { source in
                        Button {
                            categoriesOpen = false
                            requestedCategory = source.id
                            proxy.scrollTo(source.id, anchor: .top)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(source.title).font(.system(size: 23, weight: .medium)).lineLimit(2)
                                Text(source.addon.manifest.name).font(.system(size: 16)).foregroundStyle(NTVDesign.textSecondary)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(NTVActionButtonStyle()).focused($categoryFocus, equals: source.id)
                        .accessibilityIdentifier("ntv.category.\(mediaType).\(source.id)")
                    }
                }.padding(8)
            }
        }
        .padding(28).frame(width: 420).frame(maxHeight: .infinity)
        .defaultFocus($categoryFocus, viewModel.sources.first?.id)
        .background(NTVDesign.background.opacity(0.97), in: RoundedRectangle(cornerRadius: 28))
        .overlay(RoundedRectangle(cornerRadius: 28).stroke(.white.opacity(0.14)))
        .ntvHalloweenDecor(.panel)
        .onExitCommand { closeCategories() }
        .accessibilityIdentifier("ntv.catalog.\(mediaType).categoryPanel")
    }
    private func closeCategories() {
        categoriesOpen = false
        DispatchQueue.main.async { _ = ContentFocusRouter.shared.focusRowStart(ContentFocusRouter.shared.lastRowID) }
    }
}

private struct NTVCatalogShelf: View {
    @EnvironmentObject private var layout: HomeCatalogSettingsStore
    @ObservedObject var model: NTVCatalogShelfModel
    let hero: HeroFocus
    let onSelect: (MetaItem) -> Void
    let onPlayManually: (MetaItem, MetaVideo?) -> Void
    let onSeeAll: (InstalledAddon, ManifestCatalog, String) -> Void
    let onBackAtRoot: () -> Void
    let focusRequested: Bool
    var body: some View {
        Group {
            if !model.items.isEmpty {
                HomePosterRow(row: HomeRow(id: "ntv.catalog.shelf.\(model.source.id)", title: model.source.title,
                    items: model.items, addon: model.source.addon, catalog: model.source.catalog),
                    useLandscape: false, hero: hero, onSelect: onSelect,
                    onPlayManually: onPlayManually, onSeeAll: onSeeAll,
                    onBackAtStart: onBackAtRoot, accessibilityPrefix: "ntv.poster")
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    Text(model.source.title).font(.system(size: 28, weight: .semibold))
                    if model.failed {
                        Button("Réessayer ce catalogue") { Task { await model.load() } }.buttonStyle(NTVActionButtonStyle())
                    } else if model.loading { ProgressView("Chargement") }
                    else { Text("Aucun titre disponible").foregroundStyle(NTVDesign.textSecondary) }
                }
                .frame(maxWidth: .infinity, minHeight: layout.posterSize.posterWidth * 1.5 + 148, alignment: .leading)
                .padding(.horizontal, NTVViewport.horizontalInset)
            }
        }.task { await model.load() }
        .task(id: "\(focusRequested)#\(model.items.first?.id ?? "")") {
            guard focusRequested, !model.items.isEmpty else { return }
            for _ in 0..<12 {
                guard !Task.isCancelled else { return }
                if ContentFocusRouter.shared.focusRowStart("ntv.catalog.shelf.\(model.source.id)") { return }
                try? await Task.sleep(for: .milliseconds(40))
            }
        }
    }
}
