import SwiftUI
import UIKit

struct NTVCatalogSource: Identifiable {
    let addon: InstalledAddon
    let catalog: ManifestCatalog
    let id: String
    let title: String

    init(addon: InstalledAddon, catalog: ManifestCatalog) {
        self.addon = addon
        self.catalog = catalog
        // Both inputs are immutable values. Derive their opaque identity once,
        // rather than rebuilding its string and consulting the image-key
        // cache for every ForEach/focus/router lookup.
        id = ImageCache.artworkKey("\(addon.id)#\(catalog.type)#\(catalog.id)", budget: nil)
        title = NTVFrench.catalogTitle(catalog.name ?? catalog.id.capitalized)
    }
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
    var hasLoaded: Bool { loadedAt != nil }
    let source: NTVCatalogSource
    let scope: String
    private let fetch: @Sendable (NTVCatalogSource) async throws -> [MetaItem]
    init(source: NTVCatalogSource, scope: String,
         fetch: @escaping @Sendable (NTVCatalogSource) async throws -> [MetaItem] = {
             #if DEBUG
             if ProcessInfo.processInfo.arguments.contains("-ntvRowLayoutFixture") {
                 let source = $0
                 return (0..<24).map { index in
                     MetaItem(id: "fixture.catalog.\(source.catalog.id).\(index)", type: source.catalog.type,
                              name: "Titre de catalogue \(index + 1)", releaseInfo: "2025")
                 }
             }
             if ProcessInfo.processInfo.arguments.contains("-ntvUpcomingCatalogFixture") {
                 return [MetaItem(id: "fixture.future.\($0.catalog.id)", type: $0.catalog.type,
                                  name: "Sortie à venir", releaseInfo: "2999", released: "2999-01-01")]
             }
             #endif
             return try await StremioAPI.catalog(addon: $0.addon, catalog: $0.catalog)
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
                guard !NTVAnimeLibrary.shared.contains(item) else { continue }
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
    private var emptyVisibleSources: Set<String> = []
    func noteVisibleStart(sourceID: String, itemID: String?) {
        if itemID == nil { emptyVisibleSources.insert(sourceID) }
        else { emptyVisibleSources.remove(sourceID) }
    }
    var firstNavigableSourceID: String? {
        // When every loaded shelf is filtered out, its empty-state Categories
        // action still provides a reachable destination from the top menu.
        sources.first { !emptyVisibleSources.contains($0.id) }?.id ?? sources.first?.id
    }
    func adjacentNavigableSourceID(to sourceID: String, forward: Bool) -> String? {
        guard let index = sources.firstIndex(where: { $0.id == sourceID }) else { return nil }
        if forward {
            return sources.dropFirst(index + 1).first { !emptyVisibleSources.contains($0.id) }?.id
        }
        return sources.prefix(index).reversed().first { !emptyVisibleSources.contains($0.id) }?.id
    }
    func configure(addons: [InstalledAddon], type: String, scope: String) {
        let available = addons.flatMap { addon in
            (addon.manifest.catalogs ?? []).filter { $0.type == type && !$0.requiresExtra && !NTVAnimeDomain.contains($0) }
                .map { NTVCatalogSource(addon: addon, catalog: $0) }
        }
        let next = scope + "#" + available.map { "\($0.id)#\($0.catalog.hashValue)" }.joined(separator: "#")
        guard next != fingerprint else { return }
        fingerprint = next; shelves = [:]; order = []; lastSelection = nil; emptyVisibleSources = []
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
    @Environment(\.navigationIsTop) private var navigationIsTop
    @EnvironmentObject private var addons: AddonManager
    @EnvironmentObject private var profiles: ProfileStore
    @ObservedObject private var iptv = LiveTVSettingsStore.shared
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
    private struct FocusRequest {
        let sourceID: String
        let entry: ContentFocusRouter.EntryRequest
        var scrollToStart = true
    }
    @State private var requestedCategory: FocusRequest?
    @State private var restoreSelection: NTVCatalogBrowserModel.Selection?
    @State private var restoreFocusRequest: ContentFocusRouter.EntryRequest?
    @State private var menuVisible = false
    @State private var menuSourceID: String?
    @FocusState private var categoryFocus: String?
    @FocusState private var categoryTriggerFocused: Bool
    private var routerID: String { "ntv.catalog.\(mediaType).entry" }
    private var loadKey: String {
        String(profiles.activeProfileID) + "#" + iptv.routingFingerprint + "#" + addons.catalogAddons.map { "\($0.id)#\($0.manifest.catalogs?.hashValue ?? 0)" }.joined(separator: "#")
    }
    var body: some View {
        let _ = NTVRenderProbe.evaluated(.catalog)
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
                                if !viewModel.sources.isEmpty {
                                    Button {
                                        if let source = viewModel.lastSelection?.sourceID ?? viewModel.firstNavigableSourceID {
                                            openCategory(source)
                                        }
                                    } label: {
                                        Label("Catégories", systemImage: "line.3.horizontal.decrease")
                                    }
                                    .buttonStyle(NTVActionButtonStyle())
                                    .focused($categoryTriggerFocused)
                                    .onChange(of: categoryTriggerFocused) { _, focused in
                                        if focused { ContentFocusRouter.shared.noteFocused(row: routerID) }
                                    }
                                    .accessibilityIdentifier("ntv.catalog.\(mediaType).openCategories")
                                    .onMoveCommand { direction in
                                        guard categoryTriggerFocused, direction == .down,
                                              let first = viewModel.firstNavigableSourceID else { return }
                                        requestRow(first, proxy: proxy)
                                    }
                                }
                            }
                                .padding(.horizontal, NTVViewport.horizontalInset)
                                .id("catalogTop")
                            NTVCatalogSpotlight(hero: hero)
                                .frame(minHeight: 230, alignment: .topLeading)
                                .transaction { $0.animation = nil }
                                .padding(.horizontal, NTVViewport.horizontalInset)
                            if viewModel.sources.isEmpty {
                                NTVEmptyCatalog(message: "Ajoutez un addon proposant des catalogues de \(title.lowercased()).", onOpenSettings: onOpenSettings)
                                    .padding(.horizontal, NTVViewport.horizontalInset)
                            }
                            ForEach(viewModel.sources) { source in
                                NTVCatalogShelf(model: viewModel.shelf(source), hero: hero,
                                    onSelect: { item in
                                        ContentFocusRouter.shared.cancelLanding()
                                        requestedCategory = nil
                                        restoreSelection = nil; restoreFocusRequest = nil
                                        viewModel.rememberSelection(sourceID: source.id, itemID: item.id)
                                        onSelect(item)
                                    }, onPlayManually: onPlayManually,
                                    onSeeAll: onSeeAll,
                                    onBackAtRoot: onBackAtRoot,
                                    onLeftAtStart: { openCategory(source.id) }, interceptLeftEdge: navigationIsTop,
                                    onVerticalMove: { move in moveFromRow(source.id, direction: move, proxy: proxy) },
                                    onUpAtBoundary: !navigationIsTop && source.id == viewModel.firstNavigableSourceID
                                        ? { moveFromRow(source.id, direction: .up, proxy: proxy) } : nil,
                                    focusRequest: requestedCategory?.sourceID == source.id ? requestedCategory?.entry : nil,
                                    focusScrollToStart: requestedCategory?.scrollToStart ?? true,
                                    restoreItemID: restoreSelection?.sourceID == source.id ? restoreSelection?.itemID : nil,
                                    restoreFocusRequest: restoreSelection?.sourceID == source.id ? restoreFocusRequest : nil)
                                    .onFirstVisibleItem { viewModel.noteVisibleStart(sourceID: source.id, itemID: $0) }
                                    .accessibilityElement(children: .contain)
                                    .accessibilityIdentifier("ntv.catalog.shelf.\(source.id)")
                                    .id(source.id)
                            }
                        }.padding(.top, 26).padding(.bottom, 100)
                    }
                    // Vertical clipping reserves the top bar; horizontal rows
                    // retain their own focus-lift margin.
                    .focusSection()
                    .disabled(menuVisible)
                    .overlay {
                        if menuVisible { Color.black.opacity(0.3).allowsHitTesting(false) }
                    }
                    if menuVisible {
                        // Overlay the gallery: opening the menu never changes
                        // poster sizes, row spacing or the backdrop viewport.
                        categoryPanel(proxy)
                            .frame(width: 360)
                            .padding(.leading, NTVViewport.horizontalInset)
                            .padding(.vertical, 20)
                            .transition(.opacity)
                            .zIndex(1)
                    }
                }
                .task(id: isAtRoot) {
                    ContentFocusRouter.shared.cancelEntry(restoreFocusRequest)
                    restoreFocusRequest = nil
                    restoreSelection = nil
                    guard isAtRoot else {
                        ContentFocusRouter.shared.cancelEntry(requestedCategory?.entry)
                        requestedCategory = nil
                        return
                    }
                    guard let selection = viewModel.lastSelection else { return }
                    ContentFocusRouter.shared.cancelEntry(requestedCategory?.entry)
                    requestedCategory = nil
                    restoreSelection = selection
                    restoreFocusRequest = ContentFocusRouter.shared.makeEntryRequest(
                        in: "ntv.catalog.shelf.\(selection.sourceID)", kind: .restoration)
                    if selection.sourceID != viewModel.sources.first?.id {
                        proxy.scrollTo(selection.sourceID, anchor: .top)
                    }
                }
                .onAppear {
                    ContentFocusRouter.shared.register(routerID) {
                        guard let first = viewModel.firstNavigableSourceID else { return false }
                        requestRow(first, proxy: proxy); return true
                    }
                }
                .onDisappear {
                    cancelEntryRequests()
                    ContentFocusRouter.shared.unregister(routerID)
                }
            }
        }
        .foregroundStyle(theme.palette.textPrimary)
        .ignoresSafeArea(edges: .horizontal)
        .toolbar(.hidden, for: .navigationBar)
        .task(id: loadKey) {
            hero.layout = .pinnedFocus
            viewModel.configure(addons: addons.catalogAddons, type: mediaType, scope: String(profiles.activeProfileID) + "#" + iptv.routingFingerprint)
            if let first = viewModel.sources.first {
                let shelf = viewModel.shelf(first)
                await shelf.load()
                guard !Task.isCancelled else { return }
                if hero.item == nil, let item = shelf.items.first { hero.focus(item) }
            }
        }
        .onChange(of: profiles.activeProfileID) { _, _ in
            cancelEntryRequests(); restoreFocusRequest = nil
            hero.item = nil; restoreSelection = nil; requestedCategory = nil
            menuVisible = false; menuSourceID = nil; categoryFocus = nil
        }
        .onExitCommand { onBackAtRoot() }
    }
    private func categoryPanel(_ proxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Button {
                categoryFocus = viewModel.sources.first?.id
            } label: {
                Label("Catégories", systemImage: "line.3.horizontal.decrease")
                    .font(.system(size: 29, weight: .semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(NTVCategoryButtonStyle())
            .focused($categoryFocus, equals: "header")
            .accessibilityIdentifier("ntv.catalog.\(mediaType).categories")
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(viewModel.sources) { source in
                        Button { requestRow(source.id, proxy: proxy) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(source.title).font(.system(size: 29, weight: .medium)).lineLimit(2)
                                Text(source.addon.manifest.name).font(.system(size: 25))
                                    .foregroundStyle(categoryFocus == source.id ? NTVDesign.background.opacity(0.7) : NTVDesign.textSecondary)
                                    .lineLimit(1)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(NTVCategoryButtonStyle())
                        .focused($categoryFocus, equals: source.id)
                        .accessibilityIdentifier("ntv.category.\(mediaType).\(source.id)")
                    }
                }.padding(4)
            }
            .ntvHalloweenDecor(.panel)
        }
        .padding(20).frame(maxHeight: 760)
        .background {
            RoundedRectangle(cornerRadius: 20).fill(NTVDesign.surface.opacity(0.98))
                .overlay { RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(.white.opacity(0.12), lineWidth: 1) }
        }
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
            }
        }
        .onReceive(NotificationCenter.default.publisher(
            for: UIFocusSystem.movementDidFailNotification)) { note in
            // Reaching the header from the first category is a successful Up.
            // Leave the panel only on an additional Up at its actual edge.
            guard categoryFocus == "header",
                  let context = note.userInfo?[UIFocusSystem.focusUpdateContextUserInfoKey]
                    as? UIFocusUpdateContext,
                  context.focusHeading == .up else { return }
                menuVisible = false; categoryFocus = nil
                onBackAtRoot()
        }
        .onAppear { categoryFocus = menuSourceID ?? viewModel.sources.first?.id }
        .defaultFocus($categoryFocus, menuSourceID ?? viewModel.sources.first?.id)
        .onExitCommand { closeCategory(proxy) }
    }
    private func openCategory(_ sourceID: String) {
        ContentFocusRouter.shared.noteUserMovement()
        categoryTriggerFocused = false
        requestedCategory = nil; restoreSelection = nil; restoreFocusRequest = nil
        menuSourceID = sourceID
        withAnimation(PerformanceSettingsStore.shared.buttonMotion(.easeOut(duration: 0.15))) {
            menuVisible = true
        }
    }
    private func closeCategory(_ proxy: ScrollViewProxy) {
        guard let sourceID = menuSourceID ?? viewModel.sources.first?.id else {
            menuVisible = false; categoryFocus = nil; return
        }
        requestRow(sourceID, proxy: proxy)
    }
    private func requestRow(_ sourceID: String, proxy: ScrollViewProxy) {
        let keepViewport = menuVisible && menuSourceID == sourceID
        categoryFocus = nil; menuVisible = false
        viewModel.forgetSelection(); restoreSelection = nil; restoreFocusRequest = nil
        // The drawer is entered from the first poster. Returning to that same
        // row needs focus only: scrollTo(.leading) would rewrite its native
        // horizontal offset and make the posters slide after the drawer closes.
        let entry = ContentFocusRouter.shared.makeEntryRequest(in: "ntv.catalog.shelf.\(sourceID)")
        requestedCategory = FocusRequest(sourceID: sourceID, entry: entry, scrollToStart: !keepViewport)
        if !keepViewport { proxy.scrollTo(sourceID, anchor: .top) }
    }
    private func cancelEntryRequests() {
        ContentFocusRouter.shared.cancelEntry(requestedCategory?.entry)
        ContentFocusRouter.shared.cancelEntry(restoreFocusRequest)
    }
    private func moveFromRow(_ sourceID: String, direction: MoveCommandDirection, proxy: ScrollViewProxy) {
        guard direction == .up || direction == .down else { return }
        if let target = viewModel.adjacentNavigableSourceID(to: sourceID, forward: direction == .down) {
            requestRow(target, proxy: proxy)
        } else if direction == .up {
            if navigationIsTop { onBackAtRoot() }
            else {
                cancelEntryRequests()
                requestedCategory = nil; restoreSelection = nil; restoreFocusRequest = nil
                proxy.scrollTo("catalogTop", anchor: .top)
                ContentFocusRouter.shared.land(in: routerID,
                    assign: { categoryTriggerFocused = true }, landed: { categoryTriggerFocused })
            }
        }
    }
}

/// One glazed panel, simple rows: no blur or protruding focus ring per category.
private struct NTVCategoryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Chrome(configuration: configuration) }
    private struct Chrome: View {
        @Environment(\.isFocused) private var focused
        let configuration: ButtonStyle.Configuration
        var body: some View {
            configuration.label
                .foregroundStyle(focused ? NTVDesign.background : NTVDesign.textPrimary)
                .padding(.horizontal, 18).padding(.vertical, 12)
                .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 14).fill(focused ? .white.opacity(0.96) : .black.opacity(0.2)))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(focused ? 0.6 : 0.08), lineWidth: 1))
                .cardPressDip(configuration.isPressed)
        }
    }
}

private struct NTVCatalogShelf: View {
    @EnvironmentObject private var layout: HomeCatalogSettingsStore
    @FocusState private var emptyFocus: Bool
    @ObservedObject var model: NTVCatalogShelfModel
    let hero: HeroFocus
    let onSelect: (MetaItem) -> Void
    let onPlayManually: (MetaItem, MetaVideo?) -> Void
    let onSeeAll: (InstalledAddon, ManifestCatalog, String) -> Void
    let onBackAtRoot: () -> Void
    let onLeftAtStart: () -> Void
    var interceptLeftEdge = true
    let onVerticalMove: (MoveCommandDirection) -> Void
    var onUpAtBoundary: (() -> Void)? = nil
    let focusRequest: ContentFocusRouter.EntryRequest?
    var focusScrollToStart = true
    let restoreItemID: String?
    let restoreFocusRequest: ContentFocusRouter.EntryRequest?
    var firstVisibleChanged: ((String?) -> Void)?
    func onFirstVisibleItem(_ action: @escaping (String?) -> Void) -> Self {
        var copy = self; copy.firstVisibleChanged = action; return copy
    }
    var body: some View {
        Group {
            if !model.items.isEmpty {
                HomePosterRow(row: HomeRow(id: "ntv.catalog.shelf.\(model.source.id)", title: model.source.title,
                    items: model.items, addon: model.source.addon, catalog: model.source.catalog),
                    useLandscape: false, hero: hero, onSelect: onSelect,
                    onPlayManually: onPlayManually, onSeeAll: onSeeAll,
                    onBackAtStart: onBackAtRoot, accessibilityPrefix: "ntv.poster",
                    restoreItemID: restoreItemID, onVerticalMove: onVerticalMove,
                    onUpAtBoundary: onUpAtBoundary,
                    focusFirstRequest: focusRequest,
                    restoreFocusRequest: restoreFocusRequest,
                    onLeftAtStart: interceptLeftEdge ? onLeftAtStart : nil,
                    onFirstVisibleChange: firstVisibleChanged,
                    focusFirstScroll: focusScrollToStart)
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    Text(model.source.title).font(.system(size: 28, weight: .semibold))
                    if model.failed {
                        Button("Réessayer ce catalogue") { Task { await model.load() } }.buttonStyle(NTVActionButtonStyle())
                    } else if model.loading { ProgressView("Chargement") }
                    else { Text("Aucun titre disponible").foregroundStyle(NTVDesign.textSecondary) }
                    if !model.loading {
                        Button(action: onLeftAtStart) {
                            Label("Catégories", systemImage: "line.3.horizontal.decrease")
                        }
                        .buttonStyle(NTVActionButtonStyle())
                        .focused($emptyFocus)
                        .accessibilityIdentifier("ntv.catalog.empty.\(model.source.id)")
                    }
                }
                .frame(maxWidth: .infinity, minHeight: layout.posterSize.posterWidth * 1.5 + 148, alignment: .leading)
                .padding(.horizontal, NTVViewport.horizontalInset)
                .onExitCommand(perform: onBackAtRoot)
                .onMoveCommand { direction in
                    guard emptyFocus else { return }
                    if direction == .up || direction == .down { onVerticalMove(direction) }
                    if direction == .left { onLeftAtStart() }
                }
                .onChange(of: emptyFocus) { _, focused in
                    if focused { ContentFocusRouter.shared.noteFocused(row: "ntv.catalog.shelf.\(model.source.id)") }
                }
                .task(id: focusRequest) { claimEmptyEntry() }
                .onChange(of: model.loading) { _, loading in
                    if !loading { claimEmptyEntry() }
                }
            }
        }.task { await model.load() }
            .onChange(of: model.loading) { _, loading in
                if !loading && !model.failed && model.hasLoaded && model.items.isEmpty { firstVisibleChanged?(nil) }
            }
    }
    private func claimEmptyEntry() {
        guard !model.loading, model.items.isEmpty, model.hasLoaded || model.failed,
              let focusRequest,
              ContentFocusRouter.shared.consumeEntry(focusRequest) else { return }
        emptyFocus = true
    }
}
