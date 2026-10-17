import SwiftUI

/// Add a TMDB or Trakt source to a collection folder — mirrors the Android
/// editor's TMDB/Trakt pickers (presets, discover, company/person search,
/// id-based network/list/collection, and Trakt public lists), consolidated
/// into fewer screens for Siri-remote navigation.
struct CollectionSourcePickerView: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var tmdbSettings: TMDBSettingsStore
    @EnvironmentObject private var trakt: TraktStore
    let onAdd: (CollectionSourceDTO) -> Void
    let onDone: () -> Void

    private enum Tab: String, CaseIterable, Identifiable {
        case presets = "Presets"
        case discover = "Discover"
        case search = "Company / Person"
        case byID = "Network / List / Collection"
        case trakt = "Trakt List"
        var id: String { rawValue }
    }

    @State private var tab: Tab = .presets

    /// What this tab needs and doesn't have. TMDB tabs come first in the tab
    /// bar because TMDB covers every source type a collection can hold.
    private var connectionWarning: String? {
        if tab == .trakt {
            return trakt.isSignedIn ? nil
                : "Connectez Trakt dans les réglages pour afficher les contenus de vos listes."
        }
        return tmdbSettings.isEnabled ? nil
            : "Ajoutez votre clé TMDB dans Réglages → Intégrations pour afficher ces contenus."
    }

    var body: some View {
        ZStack(alignment: .top) {
            ATVBackground()
            VStack(alignment: .leading, spacing: OrivioSpacing.lg) {
                HStack {
                    Text("Ajouter un contenu TMDB ou Trakt")
                        .font(FusionType.pageTitle(theme.font))
                        .foregroundStyle(theme.palette.textPrimary)
                    Spacer()
                    Button("Terminé", action: onDone)
                        .font(.system(size: 22, weight: .semibold))
                }
                // Warn per TAB about the service that tab actually needs —
                // a Trakt list doesn't care about TMDB, and vice versa.
                if let warning = connectionWarning {
                    Text(warning)
                        .font(.system(size: 18))
                        .foregroundStyle(OrivioPrimitives.error)
                }
                tabBar
                Group {
                    switch tab {
                    case .presets: PresetsPickerContent(onAdd: onAdd)
                    case .discover: DiscoverPickerContent(onAdd: onAdd)
                    case .search: SearchPickerContent(onAdd: onAdd)
                    case .byID: ByIDPickerContent(onAdd: onAdd)
                    case .trakt: TraktListPickerContent(onAdd: onAdd)
                    }
                }
            }
            .padding(OrivioSpacing.huge)
        }
        .onExitCommand { onDone() }
    }

    private var tabBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: OrivioSpacing.sm) {
                ForEach(Tab.allCases) { t in
                    Button { tab = t } label: {
                        SourcePickerTabPill(label: t.rawValue, selected: tab == t)
                    }
                    .buttonStyle(PlainCardButtonStyle())
                }
            }
        }
        .scrollClipDisabled()
    }
}

private struct SourcePickerTabPill: View {
    @EnvironmentObject private var theme: ThemeManager
    @Environment(\.isFocused) private var isFocused
    let label: String
    let selected: Bool

    var body: some View {
        Text(label)
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(selected ? theme.palette.onSecondary : theme.palette.textSecondary)
            .padding(.horizontal, OrivioSpacing.lg)
            .padding(.vertical, OrivioSpacing.sm)
            .background(Capsule().fill(selected ? theme.palette.secondary
                        : (isFocused ? theme.palette.focusBackground : Color.white.opacity(0.08))))
            .overlay(Capsule().strokeBorder(isFocused ? theme.palette.focusRing : .clear, lineWidth: 3))
            .focusLift(OrivioFocus.card, isFocused)
    }
}

// MARK: - Presets

/// Curated one-tap TMDB sources — same catalog the Community Collections tab
/// draws from, exposed here too so a custom collection can mix them in.
enum TMDBCollectionPresets {
    static let all: [(title: String, source: CollectionSourceDTO)] = [
        ("Marvel Studios", CollectionSourceDTO(tmdbSourceType: "COMPANY", title: "Marvel Studios", tmdbId: 420, mediaType: "movie")),
        ("Walt Disney Pictures", CollectionSourceDTO(tmdbSourceType: "COMPANY", title: "Walt Disney Pictures", tmdbId: 2, mediaType: "movie")),
        ("Pixar", CollectionSourceDTO(tmdbSourceType: "COMPANY", title: "Pixar", tmdbId: 3, mediaType: "movie")),
        ("Lucasfilm", CollectionSourceDTO(tmdbSourceType: "COMPANY", title: "Lucasfilm", tmdbId: 1, mediaType: "movie")),
        ("Warner Bros.", CollectionSourceDTO(tmdbSourceType: "COMPANY", title: "Warner Bros.", tmdbId: 174, mediaType: "movie")),
        ("Universal Pictures", CollectionSourceDTO(tmdbSourceType: "COMPANY", title: "Universal Pictures", tmdbId: 33, mediaType: "movie")),
        ("Paramount Pictures", CollectionSourceDTO(tmdbSourceType: "COMPANY", title: "Paramount Pictures", tmdbId: 4, mediaType: "movie")),
        ("A24", CollectionSourceDTO(tmdbSourceType: "COMPANY", title: "A24", tmdbId: 41077, mediaType: "movie")),
        ("DC Films", CollectionSourceDTO(tmdbSourceType: "COMPANY", title: "DC Films", tmdbId: 128064, mediaType: "movie")),
        ("Netflix", CollectionSourceDTO(tmdbSourceType: "NETWORK", title: "Netflix", tmdbId: 213, mediaType: "tv")),
        ("HBO / Max", CollectionSourceDTO(tmdbSourceType: "NETWORK", title: "HBO", tmdbId: 49, mediaType: "tv")),
        ("Disney+", CollectionSourceDTO(tmdbSourceType: "NETWORK", title: "Disney+", tmdbId: 2739, mediaType: "tv")),
        ("Prime Video", CollectionSourceDTO(tmdbSourceType: "NETWORK", title: "Prime Video", tmdbId: 1024, mediaType: "tv")),
        ("Hulu", CollectionSourceDTO(tmdbSourceType: "NETWORK", title: "Hulu", tmdbId: 453, mediaType: "tv")),
        ("Apple TV+", CollectionSourceDTO(tmdbSourceType: "NETWORK", title: "Apple TV+", tmdbId: 2552, mediaType: "tv")),
        ("FX", CollectionSourceDTO(tmdbSourceType: "NETWORK", title: "FX", tmdbId: 88, mediaType: "tv")),
        ("Peacock", CollectionSourceDTO(tmdbSourceType: "NETWORK", title: "Peacock", tmdbId: 3353, mediaType: "tv")),
        ("Paramount+", CollectionSourceDTO(tmdbSourceType: "NETWORK", title: "Paramount+", tmdbId: 4330, mediaType: "tv")),
        ("Films tendance", CollectionSourceDTO(tmdbSourceType: "DISCOVER", title: "Films tendance", tmdbId: nil, mediaType: "movie", sortBy: "popularity.desc")),
        ("Séries tendance", CollectionSourceDTO(tmdbSourceType: "DISCOVER", title: "Séries tendance", tmdbId: nil, mediaType: "tv", sortBy: "popularity.desc")),
        ("Films les mieux notés", CollectionSourceDTO(tmdbSourceType: "DISCOVER", title: "Films les mieux notés", tmdbId: nil, mediaType: "movie", sortBy: "vote_average.desc")),
        ("Séries les mieux notées", CollectionSourceDTO(tmdbSourceType: "DISCOVER", title: "Séries les mieux notées", tmdbId: nil, mediaType: "tv", sortBy: "vote_average.desc")),
    ]
}

private struct PresetsPickerContent: View {
    let onAdd: (CollectionSourceDTO) -> Void
    private let columns = [GridItem(.adaptive(minimum: 280), spacing: OrivioSpacing.md)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: OrivioSpacing.md) {
                ForEach(TMDBCollectionPresets.all, id: \.title) { preset in
                    Button { onAdd(preset.source) } label: {
                        SettingsActionRow(title: preset.title, subtitle: preset.source.tmdbSourceType?.capitalized,
                                          leadingIcon: "sparkles")
                    }
                    .buttonStyle(PlainCardButtonStyle())
                }
            }
        }
    }
}

// MARK: - Discover

private struct DiscoverPickerContent: View {
    let onAdd: (CollectionSourceDTO) -> Void
    @State private var isMovie = true
    @State private var sortBy = "popularity.desc"
    @State private var genre: String?

    private static let sorts = [
        OrivioDropdownOption("popularity.desc", "Popularité"),
        OrivioDropdownOption("vote_average.desc", "Les mieux notés"),
        OrivioDropdownOption("vote_count.desc", "Les plus notés"),
        OrivioDropdownOption("primary_release_date.desc", "Les plus récents"),
    ]
    private static let genres: [(String, String)] = [
        ("28", "Action"), ("12", "Aventure"), ("16", "Animation"), ("35", "Comédie"),
        ("80", "Policier"), ("99", "Documentaire"), ("18", "Drame"), ("10751", "Famille"),
        ("14", "Fantastique"), ("36", "Histoire"), ("27", "Horreur"), ("10402", "Musique"),
        ("9648", "Mystère"), ("10749", "Romance"), ("878", "Science-fiction"), ("53", "Thriller"),
        ("10752", "Guerre"), ("37", "Western"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: OrivioSpacing.lg) {
            Picker("", selection: $isMovie) {
                Text("Films").tag(true)
                Text("Séries").tag(false)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 500)

            OrivioDropdown(title: "Trier par", selection: sortBy, options: Self.sorts) { sortBy = $0 }

            OrivioDropdown(
                title: "Genre",
                selection: genre ?? "",
                options: [OrivioDropdownOption("", "Tous")] + Self.genres.map { OrivioDropdownOption($0.0, $0.1) }
            ) { genre = $0.isEmpty ? nil : $0 }

            Button {
                let name = (genre.flatMap { id in Self.genres.first { $0.0 == id }?.1 } ?? "Découvrir")
                    + (isMovie ? " Films" : " Séries")
                let filters = genre.map { TmdbFiltersDTO(withGenres: $0) }
                onAdd(CollectionSourceDTO(
                    tmdbSourceType: "DISCOVER", title: name, tmdbId: nil,
                    mediaType: isMovie ? "movie" : "tv", sortBy: sortBy, filters: filters
                ))
            } label: {
                SettingsActionRow(title: "Ajouter un catalogue de découverte", leadingIcon: "plus.circle.fill")
            }
            .buttonStyle(PlainCardButtonStyle())
        }
    }
}

// MARK: - Search (Company / Person)

private struct SearchPickerContent: View {
    let onAdd: (CollectionSourceDTO) -> Void
    @State private var kind = 0   // 0 = company, 1 = person, 2 = director
    @State private var query = ""
    @State private var isMovie = true
    @State private var companyResults: [TMDBService.CompanySearchResult] = []
    @State private var personResults: [TMDBService.PersonSearchResult] = []
    @State private var searching = false

    var body: some View {
        VStack(alignment: .leading, spacing: OrivioSpacing.lg) {
            Picker("", selection: $kind) {
                Text("Studio").tag(0)
                Text("Distribution").tag(1)
                Text("Réalisation").tag(2)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 500)

            if kind != 0 {
                Picker("", selection: $isMovie) {
                    Text("Films").tag(true)
                    Text("Séries").tag(false)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 500)
            }

            HStack {
                TextField(kind == 0 ? "Rechercher un studio…" : "Rechercher une personne…", text: $query)
                    .font(.system(size: 24))
                    .frame(maxWidth: 600)
                    .onSubmit { Task { await search() } }
                Button("Recherche") { Task { await search() } }
                    .font(.system(size: 22, weight: .semibold))
            }

            if searching {
                ProgressView()
            } else if kind == 0 {
                ForEach(companyResults) { c in
                    Button {
                        onAdd(CollectionSourceDTO(tmdbSourceType: "COMPANY", title: c.name, tmdbId: c.id, mediaType: "movie"))
                    } label: {
                        SettingsActionRow(title: c.name, leadingIcon: "building.2.fill")
                    }
                    .buttonStyle(PlainCardButtonStyle())
                }
            } else {
                ForEach(personResults) { p in
                    Button {
                        onAdd(CollectionSourceDTO(
                            tmdbSourceType: kind == 2 ? "DIRECTOR" : "PERSON", title: p.name, tmdbId: p.id,
                            mediaType: isMovie ? "movie" : "tv"
                        ))
                    } label: {
                        SettingsActionRow(title: p.name, subtitle: p.knownFor, leadingIcon: "person.fill")
                    }
                    .buttonStyle(PlainCardButtonStyle())
                }
            }
        }
    }

    private func search() async {
        searching = true
        defer { searching = false }
        if kind == 0 {
            companyResults = await TMDBService.searchCompanies(query)
        } else {
            personResults = await TMDBService.searchPeople(query)
        }
    }
}

// MARK: - By ID (Network / List / Collection)

private struct ByIDPickerContent: View {
    let onAdd: (CollectionSourceDTO) -> Void
    @EnvironmentObject private var tmdbSettings: TMDBSettingsStore
    @State private var kind = 0   // 0 = network, 1 = list, 2 = collection
    @State private var input = ""
    @State private var resolvedName: String?
    @State private var resolvedID: Int?
    @State private var looking = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: OrivioSpacing.lg) {
            Picker("", selection: $kind) {
                Text("Chaîne").tag(0)
                Text("Liste").tag(1)
                Text("Collection").tag(2)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 600)
            .onChange(of: kind) { _, _ in resolvedName = nil; resolvedID = nil; error = nil }

            Text(kind == 0 ? "Saisissez l’identifiant TMDB de la chaîne, par exemple 213 pour Netflix."
                 : "Collez un lien themoviedb.org ou un identifiant.")
                .font(.system(size: 18))
                .foregroundStyle(.secondary)

            HStack {
                TextField(kind == 0 ? "Identifiant de la chaîne" : "URL or id", text: $input)
                    .font(.system(size: 24))
                    .frame(maxWidth: 600)
                Button("Rechercher") { Task { await lookup() } }
                    .font(.system(size: 22, weight: .semibold))
            }

            if looking { ProgressView() }
            if let error { Text(error).foregroundStyle(OrivioPrimitives.error) }

            if let resolvedName {
                Button {
                    guard let resolvedID else { return }
                    let type = kind == 0 ? "NETWORK" : (kind == 1 ? "LIST" : "COLLECTION")
                    onAdd(CollectionSourceDTO(
                        tmdbSourceType: type, title: resolvedName, tmdbId: resolvedID,
                        mediaType: kind == 0 ? "tv" : "movie"
                    ))
                } label: {
                    SettingsActionRow(title: "Ajouter « \(resolvedName) »", leadingIcon: "plus.circle.fill")
                }
                .buttonStyle(PlainCardButtonStyle())
            }
        }
    }

    private func lookup() async {
        error = nil
        resolvedName = nil
        guard let id = kind == 0 ? Int(input.trimmingCharacters(in: .whitespaces)) : TMDBService.parseTMDBID(from: input) else {
            error = "Aucun identifiant trouvé."
            return
        }
        looking = true
        defer { looking = false }
        let lang = tmdbSettings.settings.language
        let name: String?
        switch kind {
        case 0: name = await TMDBService.networkName(id: id)
        case 1: name = await TMDBService.listName(id: id, language: lang)
        default: name = await TMDBService.collectionName(id: id, language: lang)
        }
        guard let name, !name.isEmpty else {
            error = "Aucun résultat trouvé sur TMDB."
            return
        }
        resolvedID = id
        resolvedName = name
    }
}

// MARK: - Trakt list

private struct TraktListPickerContent: View {
    let onAdd: (CollectionSourceDTO) -> Void
    @State private var input = ""
    @State private var isMovie = true
    @State private var sortBy = "rank"
    @State private var sortHow = "asc"
    @State private var resolved: TraktService.PublicListInfo?
    @State private var looking = false
    @State private var error: String?

    private static let sorts = [
        OrivioDropdownOption("rank", "Ordre de la liste"), OrivioDropdownOption("added", "Date d’ajout"),
        OrivioDropdownOption("title", "Titre"), OrivioDropdownOption("released", "Date de sortie"),
        OrivioDropdownOption("popularity", "Popularité"), OrivioDropdownOption("votes", "Votes"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: OrivioSpacing.lg) {
            Text("Paste a Trakt list URL, slug, or id — public or your own.")
                .font(.system(size: 18))
                .foregroundStyle(.secondary)
            HStack {
                TextField("trakt.tv/users/.../lists/...", text: $input)
                    .font(.system(size: 24))
                    .frame(maxWidth: 600)
                Button("Rechercher") { Task { await lookup() } }
                    .font(.system(size: 22, weight: .semibold))
            }

            Picker("", selection: $isMovie) {
                Text("Films").tag(true)
                Text("Séries").tag(false)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 500)

            OrivioDropdown(title: "Trier par", selection: sortBy, options: Self.sorts) { sortBy = $0 }

            if looking { ProgressView() }
            if let error { Text(error).foregroundStyle(OrivioPrimitives.error) }

            if let resolved {
                Button {
                    onAdd(CollectionSourceDTO(
                        traktListId: resolved.traktListId, title: resolved.title,
                        mediaType: isMovie ? "movie" : "tv", sortBy: sortBy, sortHow: sortHow
                    ))
                } label: {
                    SettingsActionRow(title: "Ajouter « \(resolved.title) »", leadingIcon: "plus.circle.fill")
                }
                .buttonStyle(PlainCardButtonStyle())
            }
        }
    }

    private func lookup() async {
        error = nil
        resolved = nil
        looking = true
        defer { looking = false }
        guard let info = await TraktService.publicListInfo(input: input) else {
            error = "Cette liste Trakt est introuvable. Elle doit être publique."
            return
        }
        resolved = info
    }
}
