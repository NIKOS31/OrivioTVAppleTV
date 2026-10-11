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
    struct Selection: Equatable { let sourceID: String; let itemID: String }
    // Unpublished: remembering a clicked poster must not redraw the shelves.
    private(set) var lastSelection: Selection?
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
        fingerprint = next; shelves = [:]; order = []; lastSelection = nil
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
    func rememberSelection(sourceID: String, itemID: String) {
        guard sources.contains(where: { $0.id == sourceID }) else { return }
        lastSelection = Selection(sourceID: sourceID, itemID: itemID)
    }
    func forgetSelection() { lastSelection = nil }
}

struct NTVCatalogView: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var addons: AddonManager
    @EnvironmentObject private var profiles: ProfileStore
    @ObservedObject var viewModel: NTVCatalogBrowserModel
    let mediaType: String
    let title: String
    let isAtRoot: Bool
    let onSelect: (MetaItem) -> Void
    let onPlayManually: (MetaItem, MetaVideo?) -> Void
    let onSeeAll: (InstalledAddon, ManifestCatalog, String) -> Void
    let onBackAtRoot: () -> Void
    let onOpenSettings: () -> Void
    @State private var hero = HeroFocus()
    private struct FocusRequest { let sourceID: String; let token = UUID() }
    @State private var requestedCategory: FocusRequest?
    @State private var restoreSelection: NTVCatalogBrowserModel.Selection?
    @FocusState private var categoryFocus: String?
    private var routerID: String { "ntv.catalog.\(mediaType).categories" }
    private var loadKey: String {
        String(profiles.activeProfileID) + "#" + addons.catalogAddons.map { "\($0.id)#\($0.manifest.catalogs?.hashValue ?? 0)" }.joined(separator: "#")
    }
    var body: some View {
        ZStack(alignment: .leading) {
            NTVFocusBackdrop(hero: hero, identifier: "ntv.catalog.\(mediaType).backdrop")
            ScrollViewReader { proxy in
                HStack(alignment: .top, spacing: 24) {
                    categoryPanel(proxy)
                        .frame(width: 250)
                        .padding(.leading, 24)
                        .padding(.vertical, 26)
                    ScrollView(.vertical) {
                        LazyVStack(alignment: .leading, spacing: 22) {
                            Text(title).font(.system(size: 38, weight: .semibold))
                                .ntvHalloweenDecor(.heading)
                                .accessibilityIdentifier("ntv.catalog.\(mediaType).heading")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 24)
                                .id("catalogTop")
                            NTVCatalogSpotlight(hero: hero)
                                .frame(height: 230, alignment: .topLeading)
                                .transaction { $0.animation = nil }
                                .padding(.horizontal, 24)
                            if viewModel.sources.isEmpty {
                                NTVEmptyCatalog(message: "Ajoutez un addon proposant des catalogues de \(title.lowercased()).", onOpenSettings: onOpenSettings)
                                    .padding(.horizontal, 24)
                            }
                            ForEach(viewModel.sources) { source in
                                NTVCatalogShelf(model: viewModel.shelf(source), hero: hero,
                                    onSelect: { item in
                                        requestedCategory = nil
                                        viewModel.rememberSelection(sourceID: source.id, itemID: item.id)
                                        onSelect(item)
                                    }, onPlayManually: onPlayManually,
                                    onSeeAll: onSeeAll,
                                    onBackAtRoot: { focusCategory(source.id) },
                                    onVerticalMove: { move in moveFromRow(source.id, direction: move, proxy: proxy) },
                                    focusRequestID: requestedCategory?.sourceID == source.id ? requestedCategory?.token : nil,
                                    restoreItemID: restoreSelection?.sourceID == source.id ? restoreSelection?.itemID : nil)
                                    .accessibilityElement(children: .contain)
                                    .accessibilityIdentifier("ntv.catalog.shelf.\(source.id)")
                                    .id(source.id)
                            }
                        }.padding(.top, 26).padding(.bottom, 100)
                    }
                    // Vertical clipping reserves the top bar; horizontal rows
                    // retain their own focus-lift margin.
                    .focusSection()
                }
                .task(id: isAtRoot) {
                    restoreSelection = nil
                    guard isAtRoot, let selection = viewModel.lastSelection else { return }
                    restoreSelection = selection
                    if selection.sourceID != viewModel.sources.first?.id {
                        proxy.scrollTo(selection.sourceID, anchor: .top)
                    }
                }
                .onAppear {
                    ContentFocusRouter.shared.register(routerID) {
                        categoryFocus = "header"; return true
                    }
                }
                .onDisappear { ContentFocusRouter.shared.unregister(routerID) }
            }
        }
        .foregroundStyle(theme.palette.textPrimary)
        .ignoresSafeArea(edges: .horizontal)
        .toolbar(.hidden, for: .navigationBar)
        .task(id: loadKey) {
            hero.layout = .pinnedFocus
            viewModel.configure(addons: addons.catalogAddons, type: mediaType, scope: String(profiles.activeProfileID))
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-ntvCatalogCategoriesDemo") {
                categoryFocus = viewModel.sources.first?.id
            }
            #endif
            if let first = viewModel.sources.first {
                let shelf = viewModel.shelf(first)
                await shelf.load()
                guard !Task.isCancelled else { return }
                if hero.item == nil, let item = shelf.items.first { hero.focus(item) }
            }
        }
        .onChange(of: profiles.activeProfileID) { _, _ in
            hero.item = nil; restoreSelection = nil; requestedCategory = nil
        }
        .onExitCommand { onBackAtRoot() }
    }
    private func categoryPanel(_ proxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Button {
                categoryFocus = viewModel.sources.first?.id
            } label: {
                Label("Catégories", systemImage: "line.3.horizontal.decrease")
                    .font(.system(size: 23, weight: .semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(NTVActionButtonStyle())
            .focused($categoryFocus, equals: "header")
            .accessibilityIdentifier("ntv.catalog.\(mediaType).categories")
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(viewModel.sources) { source in
                        Button { requestRow(source.id, proxy: proxy) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(source.title).font(.system(size: 21, weight: .medium)).lineLimit(2)
                                Text(source.addon.manifest.name).font(.system(size: 15)).foregroundStyle(NTVDesign.textSecondary)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(NTVActionButtonStyle())
                        .focused($categoryFocus, equals: source.id)
                        .accessibilityIdentifier("ntv.category.\(mediaType).\(source.id)")
                    }
                }.padding(6)
            }
            .ntvHalloweenDecor(.panel)
        }
        .padding(16).frame(maxHeight: .infinity)
        .background { NTVGlassSurface(shape: RoundedRectangle(cornerRadius: 24)) }
        .focusSection()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ntv.catalog.\(mediaType).categoryPanel")
        .onChange(of: categoryFocus) { _, value in
            if value != nil { ContentFocusRouter.shared.noteFocused(row: routerID) }
        }
        .onMoveCommand { direction in
            guard let focused = categoryFocus else { return }
            if direction == .right, let source = focused == "header" ? viewModel.sources.first?.id : focused {
                requestRow(source, proxy: proxy)
            } else if direction == .up, focused == "header" {
                onBackAtRoot()
            }
        }
        .onExitCommand { onBackAtRoot() }
    }
    private func focusCategory(_ sourceID: String) {
        requestedCategory = nil; categoryFocus = sourceID
    }
    private func requestRow(_ sourceID: String, proxy: ScrollViewProxy) {
        viewModel.forgetSelection(); restoreSelection = nil
        requestedCategory = FocusRequest(sourceID: sourceID)
        proxy.scrollTo(sourceID, anchor: .top)
    }
    private func moveFromRow(_ sourceID: String, direction: MoveCommandDirection, proxy: ScrollViewProxy) {
        guard let index = viewModel.sources.firstIndex(where: { $0.id == sourceID }) else { return }
        let target = direction == .down ? index + 1 : index - 1
        if viewModel.sources.indices.contains(target) {
            requestRow(viewModel.sources[target].id, proxy: proxy)
        } else if direction == .up {
            categoryFocus = "header"
        }
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
    let onVerticalMove: (MoveCommandDirection) -> Void
    let focusRequestID: UUID?
    let restoreItemID: String?
    var body: some View {
        Group {
            if !model.items.isEmpty {
                HomePosterRow(row: HomeRow(id: "ntv.catalog.shelf.\(model.source.id)", title: model.source.title,
                    items: model.items, addon: model.source.addon, catalog: model.source.catalog),
                    useLandscape: false, hero: hero, onSelect: onSelect,
                    onPlayManually: onPlayManually, onSeeAll: onSeeAll,
                    onBackAtStart: onBackAtRoot, accessibilityPrefix: "ntv.poster",
                    restoreItemID: restoreItemID, onVerticalMove: onVerticalMove,
                    focusFirstRequestID: focusRequestID)
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
    }
}
