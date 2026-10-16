import SwiftUI

@MainActor
final class NTVAnimeModel: ObservableObject {
    @Published private(set) var feed = NTVAnimeFeed(entries: [], hasMore: false)
    @Published private(set) var loading = false
    @Published private(set) var errorMessage: String?
    private var revision = UUID()

    func load(_ request: NTVAnimeRequest) async {
        let current = UUID()
        revision = current
        feed = NTVAnimeFeed(entries: [], hasMore: false)
        errorMessage = nil
        loading = true
        do {
            let value: NTVAnimeFeed
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-ntvAnimeFixture") {
                value = NTVAnimeFixture.feed(for: request)
            } else { value = try await NTVAnimeService.shared.load(request) }
            #else
            value = try await NTVAnimeService.shared.load(request)
            #endif
            guard !Task.isCancelled, revision == current else { return }
            feed = value
        } catch is CancellationError { return }
        catch {
            guard !Task.isCancelled, revision == current else { return }
            errorMessage = (error as? NTVAnimeError) == .limited
                ? "Le planning est temporairement limité. Patiente un peu avant de réessayer."
                : "Impossible de charger les informations des animés pour le moment."
        }
        if revision == current { loading = false }
    }
}

struct NTVAnimeView: View {
    private enum Section: String, CaseIterable { case season = "Cette saison", calendar = "Planning" }
    @StateObject private var model = NTVAnimeModel()
    @State private var section: Section = .season
    // A calendar snapshot is seeded once, then refreshed on foreground entry.
    @State private var days = NTVAnimeDay.week(containing: Date())
    @State private var selectedDay = Calendar.current.startOfDay(for: Date())
    @State private var seasonRequest = NTVAnimeRequest.season(at: Date())
    @State private var selection: NTVAnimeMedia?
    @State private var selectedEntryID: String?
    @State private var pendingSearch: String?
    @State private var refresh = 0
    @FocusState private var focus: String?
    @Environment(\.scenePhase) private var scenePhase
    let onSearch: (String) -> Void
    let onBackAtRoot: () -> Void

    private var request: NTVAnimeRequest {
        if section == .calendar, let day = days.first(where: { $0.contains(selectedDay) }) { return .day(day) }
        return seasonRequest
    }
    private var requestID: String { request.cacheKey + ".\(refresh)" }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 20) {
                Text("Animés").font(.system(size: 38, weight: .semibold))
                    .accessibilityIdentifier("ntv.anime.heading")
                Spacer()
                ForEach(Section.allCases, id: \.self) { value in
                    Button { section = value } label: {
                        Label(value.rawValue, systemImage: value == .calendar ? "calendar" : "sparkles")
                    }
                    .buttonStyle(NTVActionButtonStyle())
                    .focused($focus, equals: value.rawValue)
                    .accessibilityValue(section == value ? "Sélectionné" : "")
                    .accessibilityIdentifier(value == .calendar ? "ntv.anime.planning" : "ntv.anime.season")
                    .overlay(alignment: .bottom) {
                        if section == value { Capsule().fill(NTVDesign.textPrimary).frame(width: 24, height: 3).padding(.bottom, 4) }
                    }
                }
            }
            .focusSection()

            if section == .calendar {
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
            } else {
                Text("Les animés de la saison, à retrouver dans tes addons.")
                    .font(.system(size: 26)).foregroundStyle(NTVDesign.textSecondary)
            }

            content
        }
        .padding(.horizontal, NTVViewport.horizontalInset)
        .padding(.top, 28)
        .foregroundStyle(NTVDesign.textPrimary)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(NTVDesign.background.ignoresSafeArea())
        .ignoresSafeArea(edges: .horizontal)
        .task(id: requestID) { await model.load(request) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                seasonRequest = .season(at: Date())
                days = NTVAnimeDay.week(containing: Date())
                if !days.contains(where: { $0.contains(selectedDay) }) { selectedDay = Calendar.current.startOfDay(for: Date()) }
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
        } else if model.feed.entries.isEmpty {
            VStack(spacing: 20) {
                Image(systemName: "calendar").font(.system(size: 48))
                Text("Aucune diffusion renseignée").font(.title2)
                Text("Le planning peut encore évoluer.").foregroundStyle(NTVDesign.textSecondary)
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
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: section == .calendar ? 470 : 238), spacing: 28)], spacing: 28) {
                    ForEach(model.feed.entries) { entry in
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
                if model.feed.hasMore {
                    Text(section == .calendar ? "Les 50 premières diffusions sont affichées." : "Une sélection de 24 animés de la saison.")
                        .font(.system(size: 23)).foregroundStyle(NTVDesign.textSecondary).padding(.top, 16)
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

/// One stable banner for the season. No carousel timer, animated blur, or
/// artwork replacement on each focus movement; image decoding is shared.
private struct NTVAnimeFeature: View {
    @Environment(\.isFocused) private var focused
    let media: NTVAnimeMedia
    var body: some View {
        ZStack(alignment: .leading) {
            RemoteImage(url: media.backdrop, maxDimension: 1600)
                .frame(height: 232).clipped()
            LinearGradient(colors: [NTVDesign.background, NTVDesign.background.opacity(0.82), .clear],
                           startPoint: .leading, endPoint: .trailing)
            VStack(alignment: .leading, spacing: 16) {
                Text("À L’AFFICHE CETTE SAISON").font(.system(size: 23, weight: .medium)).tracking(2)
                    .foregroundStyle(NTVDesign.textSecondary)
                Text(media.displayTitle).font(.system(size: 38, weight: .semibold)).lineLimit(2)
                Label("Voir la fiche", systemImage: "info.circle").font(.system(size: 26, weight: .medium))
            }
            .frame(maxWidth: 760, alignment: .leading).padding(32)
        }
        .frame(maxWidth: .infinity).frame(height: 232)
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
