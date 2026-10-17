import SwiftUI

@MainActor
final class NTVAnimeModel: ObservableObject {
    typealias Loader = @Sendable (NTVAnimeRequest, Int) async throws -> NTVAnimeFeed
    struct Snapshot {
        var feed = NTVAnimeFeed(entries: [], hasMore: false)
        var visibleEntries: [NTVAnimeEntry] = []
        var loading = false
        var loadingMore = false
        var errorMessage: String?
        var paginationError: String?
        var pageLimitReached = false
    }
    @Published private(set) var snapshot = Snapshot()
    var feed: NTVAnimeFeed { snapshot.feed }
    var loading: Bool { snapshot.loading }
    var errorMessage: String? { snapshot.errorMessage }
    private let loader: Loader
    private var selection: NTVAnimeRequest?
    private(set) var page = 0
    private var following: Set<Int>?
    private var paginationTask: Task<Void, Never>?
    private var revision = UUID()
    private var refreshToken = 0

    init(loader: @escaping Loader = { request, page in
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ntvAnimeFixture") {
            return NTVAnimeFixture.feed(for: request, page: page)
        }
        #endif
        return try await NTVAnimeService.shared.load(request, page: page)
    }) { self.loader = loader }

    func filterFollowing(_ ids: Set<Int>?) {
        guard following != ids else { return }
        following = ids
        var next = snapshot
        next.visibleEntries = visible(next.feed.entries)
        snapshot = next
    }
    private func visible(_ entries: [NTVAnimeEntry]) -> [NTVAnimeEntry] {
        guard let following else { return entries }
        return entries.filter { following.contains($0.media.id) }
    }
    func suspend() {
        revision = UUID()
        paginationTask?.cancel(); paginationTask = nil
        var next = snapshot
        next.loading = false; next.loadingMore = false
        snapshot = next
    }
    func load(_ request: NTVAnimeRequest, refresh: Int = 0) async {
        // Returning from a detail cover must keep the loaded pages and IDs.
        if selection == request, page > 0, refreshToken == refresh, snapshot.errorMessage == nil { return }
        paginationTask?.cancel(); paginationTask = nil
        let current = UUID()
        revision = current
        selection = request; refreshToken = refresh; page = 0
        snapshot = Snapshot(loading: true)
        do {
            let value = try await loader(request, 1)
            guard !Task.isCancelled, revision == current else { return }
            page = 1
            snapshot = Snapshot(feed: value, visibleEntries: visible(value.entries))
        } catch {
            guard revision == current else { return }
            snapshot = Snapshot(errorMessage: error is CancellationError || Task.isCancelled ? nil : Self.message(error))
        }
    }
    func requestMore() {
        guard paginationTask == nil, !snapshot.loading, !snapshot.loadingMore, snapshot.feed.hasMore else { return }
        let current = revision
        paginationTask = Task { [weak self] in
            guard let self else { return }
            await self.loadMore()
            if self.revision == current { self.paginationTask = nil }
        }
    }
    func loadMore() async {
        guard let selection, page > 0, page < NTVAnimeService.maximumPages,
              !snapshot.loading, !snapshot.loadingMore, snapshot.feed.hasMore else { return }
        let current = revision, requestedPage = page + 1
        var next = snapshot
        next.loadingMore = true; next.paginationError = nil
        snapshot = next
        do {
            let value = try await loader(selection, requestedPage)
            guard !Task.isCancelled, revision == current else { return }
            var seen = Set(snapshot.feed.entries.map(\.id))
            let entries = snapshot.feed.entries + value.entries.filter { seen.insert($0.id).inserted }
            page = requestedPage
            let capped = page == NTVAnimeService.maximumPages && value.hasMore
            snapshot = Snapshot(feed: NTVAnimeFeed(entries: entries, hasMore: value.hasMore && !capped),
                visibleEntries: visible(entries), pageLimitReached: capped)
        } catch {
            guard revision == current else { return }
            var failed = snapshot
            failed.loadingMore = false
            failed.paginationError = error is CancellationError || Task.isCancelled ? nil : Self.message(error)
            snapshot = failed
        }
    }
    private static func message(_ error: Error) -> String {
        (error as? NTVAnimeError) == .limited
            ? "AniList limite temporairement les demandes. Patiente un peu avant de réessayer."
            : "Impossible de charger les informations des animés pour le moment."
    }
}

struct NTVAnimeView: View {
    private enum Section: String, CaseIterable { case season = "Cette saison", calendar = "Planning", library = "Ma liste" }
    @StateObject private var model = NTVAnimeModel()
    @State private var section: Section = .season
    // A calendar snapshot is seeded once, then refreshed on foreground entry.
    @State private var days = NTVAnimeDay.week(containing: Date())
    @State private var selectedDay = Calendar.current.startOfDay(for: Date())
    @State private var seasonRequest = NTVAnimeRequest.season(at: Date())
    @State private var followsCurrentSeason = true
    @State private var followsCurrentWeek = true
    @State private var followingOnly = false
    @State private var selection: NTVAnimeMedia?
    @State private var selectedEntryID: String?
    @State private var pendingSearch: String?
    @State private var refresh = 0
    @FocusState private var focus: String?
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var profiles: ProfileStore
    @ObservedObject private var follows = NTVAnimeFollows.shared
    let onSearch: (String) -> Void
    let onOpenItem: (MetaItem) -> Void
    let onBackAtRoot: () -> Void

    private var request: NTVAnimeRequest {
        if section == .calendar, let day = days.first(where: { $0.contains(selectedDay) }) { return .day(day) }
        return seasonRequest
    }
    private var requestID: String { request.cacheKey + ".\(refresh).p\(profiles.activeProfileID)" }
    private var profileFollowing: Set<Int>? { section == .calendar && followingOnly ? follows.ids(profile: profiles.activeProfileID) : nil }
    private var followingRevision: String { "\(profiles.activeProfileID).\(follows.revision).\(followingOnly).\(section.rawValue)" }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 20) {
                Text("Animés").font(.system(size: 38, weight: .semibold))
                    .accessibilityIdentifier("ntv.anime.heading")
                Spacer()
                ForEach(Section.allCases, id: \.self) { value in
                    Button { section = value } label: {
                        Label(value.rawValue, systemImage: value == .calendar ? "calendar" : value == .library ? "bookmark" : "sparkles")
                    }
                    .buttonStyle(NTVActionButtonStyle())
                    .focused($focus, equals: value.rawValue)
                    .accessibilityValue(section == value ? "Sélectionné" : "")
                    .accessibilityIdentifier(value == .calendar ? "ntv.anime.planning" : value == .library ? "ntv.anime.library" : "ntv.anime.season")
                    .overlay(alignment: .bottom) {
                        if section == value { Capsule().fill(NTVDesign.textPrimary).frame(width: 24, height: 3).padding(.bottom, 4) }
                    }
                }
                Button { onSearch("") } label: { Image(systemName: "magnifyingglass") }
                    .buttonStyle(NTVActionButtonStyle())
                    .accessibilityLabel("Rechercher dans mes sources d’animés")
                    .accessibilityIdentifier("ntv.anime.sources")
            }
            .focusSection()

            if section == .calendar {
                calendarControls
                HStack(spacing: 14) {
                    ForEach(days) { day in
                        Button { selectedDay = day.start } label: {
                            VStack(spacing: 5) {
                                Text(day.start.formatted(.dateTime.locale(Locale(identifier: "fr_FR")).weekday(.abbreviated)))
                                Text(day.start.formatted(.dateTime.day())).fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(NTVActionButtonStyle())
                        .focused($focus, equals: "day.\(day.id)")
                        .accessibilityLabel(day.start.formatted(.dateTime.locale(Locale(identifier: "fr_FR")).weekday(.wide).day().month(.wide)))
                        .accessibilityValue(day.contains(selectedDay) ? "Sélectionné" : "")
                        .accessibilityIdentifier("ntv.anime.day.\(day.id)")
                        .overlay(alignment: .bottom) {
                            if day.contains(selectedDay) { Capsule().fill(NTVDesign.textPrimary).frame(width: 24, height: 3).padding(.bottom, 4) }
                        }
                    }
                }
                .focusSection()
                Text("Heures locales · \(TimeZone.current.identifier) · La diffusion ne garantit pas une source disponible.")
                    .font(.system(size: 24)).foregroundStyle(NTVDesign.textSecondary)
            } else if section == .season {
                seasonControls
            }

            if section == .library {
                NTVAnimeSavedLibrary(onSelect: onOpenItem, onSelectFollow: { media in
                    selectedEntryID = nil
                    selection = media
                })
            } else { content }
        }
        .padding(.horizontal, NTVViewport.horizontalInset)
        .padding(.top, 28)
        .foregroundStyle(NTVDesign.textPrimary)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(NTVDesign.background.ignoresSafeArea())
        .ignoresSafeArea(edges: .horizontal)
        .task(id: requestID + "." + section.rawValue) {
            guard section != .library else { return }
            model.filterFollowing(profileFollowing)
            await model.load(request, refresh: refresh)
        }
        .onChange(of: followingRevision) { _, _ in model.filterFollowing(profileFollowing) }
        .onDisappear { model.suspend() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                if followsCurrentSeason { seasonRequest = .season(at: Date()) }
                if followsCurrentWeek {
                    days = NTVAnimeDay.week(containing: Date())
                    if !days.contains(where: { $0.contains(selectedDay) }) { selectedDay = Calendar.current.startOfDay(for: Date()) }
                }
            }
        }
        .defaultFocus($focus, Section.season.rawValue)
        .onExitCommand { onBackAtRoot() }
        .fullScreenCover(item: $selection, onDismiss: {
            if let title = pendingSearch {
                pendingSearch = nil
                onSearch(title)
            } else { focus = selectedEntryID }
        }) { media in
            NTVAnimeDetail(media: media) {
                // Change tabs only after the cover actually closes. Otherwise
                // tvOS can leave its focus environment attached to a stale tab.
                pendingSearch = media.searchTitle
                selection = nil
            }
        }
    }

    private var seasonControls: some View {
        HStack(spacing: 24) {
            OrivioDropdown(title: "Saison", subtitle: "", icon: "leaf",
                selection: seasonRequest.seasonName ?? "FALL",
                options: NTVAnimeRequest.seasons.map { OrivioDropdownOption($0.0, $0.1) }) { name in
                    followsCurrentSeason = false
                    seasonRequest = .season(year: seasonRequest.seasonYear ?? Calendar.current.component(.year, from: Date()), name: name)
                }
                .frame(maxWidth: 340)
                .accessibilityIdentifier("ntv.anime.seasonPicker")
            OrivioDropdown(title: "Année", subtitle: "", icon: "calendar",
                selection: String(seasonRequest.seasonYear ?? Calendar.current.component(.year, from: Date())),
                options: (1900...(Calendar.current.component(.year, from: Date()) + 1)).reversed().map {
                    OrivioDropdownOption(String($0), String($0))
                }) { year in
                    guard let value = Int(year), (1900...2200).contains(value) else { return }
                    followsCurrentSeason = false
                    seasonRequest = .season(year: value, name: seasonRequest.seasonName ?? "FALL")
                }
                .frame(maxWidth: 290)
                .accessibilityIdentifier("ntv.anime.yearPicker")
            Button("Saison actuelle") {
                followsCurrentSeason = true; seasonRequest = .season(at: Date())
            }
            .buttonStyle(NTVActionButtonStyle())
            .accessibilityIdentifier("ntv.anime.currentSeason")
            Spacer(minLength: 0)
        }.focusSection()
    }

    private var calendarControls: some View {
        HStack(spacing: 20) {
            Button { changeWeek(-1) } label: { Image(systemName: "chevron.left") }
                .buttonStyle(NTVActionButtonStyle()).accessibilityLabel("Semaine précédente")
                .accessibilityIdentifier("ntv.anime.previousWeek")
            Button("Cette semaine") {
                followsCurrentWeek = true
                selectedDay = Calendar.current.startOfDay(for: Date())
                days = NTVAnimeDay.week(containing: selectedDay)
            }
            .buttonStyle(NTVActionButtonStyle()).accessibilityIdentifier("ntv.anime.currentWeek")
            Button { changeWeek(1) } label: { Image(systemName: "chevron.right") }
                .buttonStyle(NTVActionButtonStyle()).accessibilityLabel("Semaine suivante")
                .accessibilityIdentifier("ntv.anime.nextWeek")
            Spacer(minLength: 10)
            if let first = days.first, let last = days.last {
                Text(first.start.formatted(.dateTime.day().month(.abbreviated)) + " – " + last.start.formatted(.dateTime.day().month(.abbreviated).year()))
                    .font(.system(size: 25)).foregroundStyle(NTVDesign.textSecondary)
            }
            Button { followingOnly.toggle() } label: {
                Label(followingOnly ? "Mes animés suivis" : "Tous les animés", systemImage: followingOnly ? "bookmark.fill" : "calendar")
            }
            .buttonStyle(NTVActionButtonStyle())
            .accessibilityValue(followingOnly ? "Filtre personnel activé" : "Toutes les diffusions")
            .accessibilityIdentifier("ntv.anime.followingOnly")
        }.focusSection()
    }
    private func changeWeek(_ offset: Int) {
        guard let shifted = Calendar.current.date(byAdding: .weekOfYear, value: offset, to: selectedDay),
              (1971...2037).contains(Calendar.current.component(.year, from: shifted)) else { return }
        followsCurrentWeek = false
        selectedDay = shifted
        days = NTVAnimeDay.week(containing: shifted)
    }

    @ViewBuilder private var content: some View {
        if model.loading {
            VStack(spacing: 20) { ProgressView(); Text("Chargement des animés…") }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let message = model.errorMessage {
            VStack(spacing: 24) {
                Text(message).font(.title2).multilineTextAlignment(.center)
                Button("Réessayer") { refresh += 1 }.buttonStyle(NTVActionButtonStyle())
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                if section == .season, let entry = model.feed.entries.first {
                    Button { open(entry, focusID: "featured") } label: { NTVAnimeFeature(media: entry.media) }
                        .buttonStyle(PlainCardButtonStyle())
                        .focused($focus, equals: "featured")
                        .accessibilityLabel("À l’affiche : " + entry.media.displayTitle)
                        .accessibilityIdentifier("ntv.anime.featured")
                        .padding(.bottom, 24)
                    HStack(alignment: .firstTextBaseline) {
                        Text("À suivre cette saison").font(.system(size: 30, weight: .semibold))
                        Spacer()
                        Text(seasonRequest.seasonLabel ?? "Cette saison")
                            .font(.system(size: 25)).foregroundStyle(NTVDesign.textSecondary)
                    }
                    .padding(.bottom, 22)
                }
                LazyVGrid(columns: section == .calendar
                          ? [GridItem(.flexible(), spacing: 28), GridItem(.flexible(), spacing: 28)]
                          : [GridItem(.adaptive(minimum: 238), spacing: 28)], spacing: 28) {
                    ForEach(model.snapshot.visibleEntries) { entry in
                        Button { open(entry, focusID: entry.id) } label: {
                            if section == .calendar { NTVAnimeCard(entry: entry) }
                            else { NTVAnimePoster(media: entry.media) }
                        }
                            .buttonStyle(PlainCardButtonStyle())
                            .focused($focus, equals: entry.id)
                            .accessibilityLabel(entry.media.displayTitle + (entry.episode.map { ", épisode \($0)" } ?? ""))
                            .accessibilityIdentifier("ntv.anime.card.\(entry.id)")
                    }
                }
                if model.snapshot.visibleEntries.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(followingOnly && section == .calendar ? "Aucun animé suivi dans les pages chargées" : section == .calendar ? "Aucune diffusion renseignée" : "Aucun animé dans cette sélection")
                            .font(.system(size: 30, weight: .semibold))
                        Text(followingOnly && section == .calendar
                             ? "Ajoute des animés à suivre depuis leur fiche. Tu peux aussi charger la suite ou afficher toutes les diffusions."
                             : "Change de date ou de saison. Le planning peut encore évoluer.")
                            .font(.system(size: 26)).foregroundStyle(NTVDesign.textSecondary)
                    }.padding(.vertical, 28)
                }
                if let error = model.snapshot.paginationError {
                    Text(error).font(.system(size: 26)).foregroundStyle(NTVDesign.textSecondary).padding(.top, 20)
                }
                // The footer stays mounted through an append, including the last
                // page, so a focused load button does not vanish underneath tvOS.
                Button {
                    if model.feed.hasMore { model.requestMore() }
                    else { refresh += 1 }
                } label: {
                    HStack(spacing: 14) {
                        if model.snapshot.loadingMore { ProgressView() }
                        Text(model.snapshot.loadingMore ? "Chargement…" : model.feed.hasMore ? model.snapshot.paginationError == nil ? "Charger la suite" : "Réessayer la suite" : "Actualiser la sélection")
                    }.frame(minWidth: 260)
                }
                .buttonStyle(NTVActionButtonStyle())
                .focused($focus, equals: "pagination")
                .accessibilityIdentifier("ntv.anime.loadMore")
                .padding(.top, 24)
                if model.snapshot.pageLimitReached {
                    Text("Limite de chargement atteinte. Affine ta sélection pour parcourir d’autres titres.")
                        .font(.system(size: 24)).foregroundStyle(NTVDesign.textSecondary).padding(.top, 16)
                }
                Text("Informations de diffusion : AniList · Disponibilité à vérifier dans tes addons")
                    .font(.system(size: 22)).foregroundStyle(NTVDesign.textSecondary).padding(.top, 20)
                }
                .padding(12)
            }
            .padding(.horizontal, -12)
            .padding(.bottom, 48)
        }
    }

    private func open(_ entry: NTVAnimeEntry, focusID: String) {
        selectedEntryID = focusID
        selection = entry.media
    }
}

/// Seanime reference: wide artwork, cover + concise metadata, then a clearly
/// separated poster gallery. The composition stays fixed when the image loads.
/// No carousel timer or artwork replacement on each focus movement.
private struct NTVAnimeFeature: View {
    @Environment(\.isFocused) private var focused
    let media: NTVAnimeMedia
    var body: some View {
        ZStack(alignment: .leading) {
            RemoteImage(url: media.backdrop, maxDimension: 1600)
                .frame(height: 300).clipped()
            LinearGradient(colors: [NTVDesign.background.opacity(0.98), NTVDesign.background.opacity(0.88), .clear],
                           startPoint: .leading, endPoint: .trailing)
            LinearGradient(colors: [.clear, NTVDesign.background.opacity(0.7)], startPoint: .top, endPoint: .bottom)
            HStack(alignment: .center, spacing: 32) {
                RemoteImage(url: media.artwork, maxDimension: 400)
                    .frame(width: 150, height: 225)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 14) {
                    Text("À L’AFFICHE CETTE SAISON").font(.system(size: 23, weight: .medium)).tracking(1.5)
                        .foregroundStyle(NTVDesign.textSecondary)
                    Text(media.displayTitle).font(.system(size: 40, weight: .semibold)).lineLimit(2)
                    Text(verbatim: media.summary).font(.system(size: 26)).lineLimit(2)
                        .foregroundStyle(NTVDesign.textSecondary)
                    Label("Explorer cet animé", systemImage: "arrow.right")
                        .font(.system(size: 26, weight: .semibold))
                }
                .frame(maxWidth: 780, alignment: .leading)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity).frame(height: 300)
        .background(NTVDesign.surface)
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay { RoundedRectangle(cornerRadius: 22).strokeBorder(.white.opacity(focused ? 0.85 : 0.12), lineWidth: focused ? 3 : 1) }
    }
}

private struct NTVAnimePoster: View {
    @Environment(\.isFocused) private var focused
    let media: NTVAnimeMedia
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Color.clear.aspectRatio(2.0 / 3.0, contentMode: .fit)
                .overlay { RemoteImage(url: media.artwork, maxDimension: 640) }
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(alignment: .topLeading) {
                    Text(media.formatLabel).font(.system(size: 21, weight: .semibold))
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(.black.opacity(0.76), in: Capsule())
                        .padding(12)
                }
                .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(focused ? 0.9 : 0.08), lineWidth: focused ? 3 : 1) }
            Text(media.displayTitle).font(.system(size: 27, weight: .semibold)).lineLimit(2)
                .frame(height: 68, alignment: .topLeading)
            Text(media.episodes.map { "\($0) épisodes" } ?? "Fiche AniList")
                .font(.system(size: 23)).foregroundStyle(NTVDesign.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .scaleEffect(focused ? 1.025 : 1)
    }
}

private struct NTVAnimeCard: View {
    @Environment(\.isFocused) private var focused
    let entry: NTVAnimeEntry
    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            RemoteImage(url: entry.media.artwork, maxDimension: 320)
                .frame(width: 142, height: 212)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 14) {
                if let date = entry.airingAt {
                    Text(date.formatted(.dateTime.locale(Locale(identifier: "fr_FR")).hour().minute()))
                        .font(.system(size: 30, weight: .semibold).monospacedDigit())
                }
                Text(entry.media.displayTitle).font(.system(size: 29, weight: .semibold)).lineLimit(3)
                if let episode = entry.episode { Text("Épisode \(episode)").font(.system(size: 25)) }
                else if let count = entry.media.episodes, count > 0 { Text("\(count) épisodes").font(.system(size: 25)) }
                Spacer(minLength: 0)
                Text("Vérifier mes sources").font(.system(size: 23)).foregroundStyle(NTVDesign.textSecondary)
            }
            .frame(maxWidth: .infinity, minHeight: 212, alignment: .topLeading)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(NTVDesign.textPrimary)
        .background(focused ? NTVDesign.raised : NTVDesign.surface, in: RoundedRectangle(cornerRadius: 20))
        .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(focused ? Color.white.opacity(0.85) : .white.opacity(0.09), lineWidth: focused ? 3 : 1) }
        .scaleEffect(focused ? 1.025 : 1)
    }
}

private struct NTVAnimeDetail: View {
    @Environment(\.dismiss) private var dismiss
    let media: NTVAnimeMedia
    let search: () -> Void
    @FocusState private var searchFocused: Bool
    @ObservedObject private var follows = NTVAnimeFollows.shared
    @EnvironmentObject private var profiles: ProfileStore
    @State private var followError = false
    var body: some View {
        HStack(alignment: .center, spacing: 60) {
            RemoteImage(url: media.artwork, maxDimension: 900)
                .frame(width: 380, height: 570).clipShape(RoundedRectangle(cornerRadius: 24))
            VStack(alignment: .leading, spacing: 30) {
                Text(media.displayTitle).font(.system(size: 46, weight: .semibold)).lineLimit(3)
                ScrollView { Text(verbatim: media.summary).font(.system(size: 29)).foregroundStyle(NTVDesign.textSecondary) }
                    .frame(maxHeight: 260)
                Text("La numérotation et la disponibilité peuvent varier selon les sources.")
                    .font(.system(size: 24)).foregroundStyle(NTVDesign.textSecondary)
                HStack(spacing: 24) {
                    Button("Chercher dans mes addons", action: search)
                        .buttonStyle(NTVActionButtonStyle()).focused($searchFocused)
                        .accessibilityIdentifier("ntv.anime.searchSources")
                    Button("Retour") { dismiss() }.buttonStyle(NTVActionButtonStyle())
                }
                Button {
                    followError = !follows.toggle(media, profile: profiles.activeProfileID)
                } label: {
                    Label(follows.contains(media.id, profile: profiles.activeProfileID) ? "Ne plus suivre" : "Suivre cet animé",
                          systemImage: follows.contains(media.id, profile: profiles.activeProfileID) ? "bookmark.fill" : "bookmark")
                }
                .buttonStyle(NTVActionButtonStyle())
                .accessibilityIdentifier("ntv.anime.follow")
                if followError {
                    Text("Impossible de modifier la liste. Elle peut contenir jusqu’à 200 animés.")
                        .font(.system(size: 25)).foregroundStyle(NTVDesign.textSecondary)
                }
                Text("Métadonnées AniList").font(.system(size: 22)).foregroundStyle(NTVDesign.textSecondary)
            }
        }
        .padding(90)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(NTVDesign.background.ignoresSafeArea())
        .foregroundStyle(NTVDesign.textPrimary)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ntv.anime.detail")
        .defaultFocus($searchFocused, true)
        .onExitCommand { dismiss() }
    }
}
