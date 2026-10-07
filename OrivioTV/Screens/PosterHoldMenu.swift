import SwiftUI

// Shared hold-Select (long-press) context menus for poster / continue-watching
// cards, used by every theme so hold-down behaves the same everywhere. Built as
// direct ViewModifiers that read their own stores from the environment, so they
// drop onto any card without threading dependencies.
//
// NOTE on the Apple TV ("Modern") theme: the system `CardButtonStyle` (its
// parallax platter) swallows `.contextMenu`, so cards that need a working hold
// menu there use the flat card style instead (see `mediaCardButtonStyle`). The
// parallax stays on the browse cards; only the Continue Watching row opts out.

// MARK: - Menu that only rebuilds when it would read differently

/// A `.contextMenu` that SwiftUI rebuilds only when `key` changes.
///
/// A context menu's items are re-evaluated whenever the view carrying it
/// re-renders — and if that happens while the menu is OPEN, tvOS reloads its
/// rows under the viewer: the white focus highlight drops out for ~200ms and
/// comes back (measured in the sim, frame by frame). The menus here observe
/// whole stores (library, watched, progress), so any change anywhere in them —
/// a sync pull landing, another title's progress — re-rendered every visible
/// card's menu. That was the "flicker in the white of the focus".
///
/// `key` must cover everything the menu SHOWS and every value its actions
/// capture, because a skipped rebuild keeps the previous closures. Used
/// through a ViewModifier, `content` is the modifier's proxy, so the card
/// itself keeps updating normally; only the menu is held.
struct StableContextMenu<Content: View, MenuItems: View>: View, Equatable {
    let content: Content
    let key: String
    @ViewBuilder let menuItems: () -> MenuItems

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.key == rhs.key }

    var body: some View {
        content.contextMenu(menuItems: menuItems)
    }
}

// MARK: - Poster hold menu (Details / Library / Watched)

struct PosterHoldMenu: ViewModifier {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var watched: WatchedStore
    let item: MetaItem
    let onDetails: () -> Void

    func body(content: Content) -> some View {
        // Read here, so the menu below rebuilds only when THIS title's answers
        // change (see StableContextMenu).
        let inLibrary = library.contains(item)
        let isWatched = !item.isSeries && watched.isWatched(item)
        StableContextMenu(content: content, key: "\(item.id)|\(inLibrary)|\(isWatched)") {
            // tvOS only evaluates this closure when it is about to PRESENT the
            // menu, so reaching this line proves the hold was accepted.
            let _ = HoldProbe.log("MENU BUILT — poster \(item.name)")
            Button { onDetails() } label: { Label("Go to Details", systemImage: "info.circle") }
            Button { library.toggle(item) } label: {
                Label(inLibrary ? "Retirer de la bibliothèque" : "Ajouter à la bibliothèque",
                      systemImage: inLibrary ? "bookmark.slash" : "bookmark")
            }
            // Movies only. `WatchedStore.isWatched(_ meta:)` is hard-false for a
            // series, so on a show poster this read "Mark as Watched" forever,
            // never showed the tick, and wrote a show-level record nothing
            // reads — a dead toggle. Series watched state lives per episode.
            if !item.isSeries {
                Button { watched.toggleMovie(item) } label: {
                    Label(isWatched ? "Marquer comme non vu" : "Marquer comme vu",
                          systemImage: isWatched ? "eye.slash" : "checkmark.circle")
                }
            }
        }
        .equatable()
    }
}

extension View {
    /// Standard poster hold-Select menu (Details / Library / Watched).
    func posterHoldMenu(_ item: MetaItem, onDetails: @escaping () -> Void) -> some View {
        modifier(PosterHoldMenu(item: item, onDetails: onDetails))
    }

    /// Optional-item variant — no-ops when a card has no resolved `MetaItem`
    /// (some theme cards only carry a lightweight title until selected).
    @ViewBuilder
    func posterHoldMenu(ifAvailable item: MetaItem?, onDetails: @escaping () -> Void) -> some View {
        if let item { posterHoldMenu(item, onDetails: onDetails) } else { self }
    }
}

// MARK: - Shared watched badge

/// A small "watched" tick shown on a movie poster once it's been marked watched,
/// so every theme surfaces watched state consistently. Series aren't badged at
/// the card level (their episodes carry watched state individually).
struct WatchedTickBadge: View {
    var body: some View {
        Image(systemName: "checkmark")
            .font(.system(size: 15, weight: .black))
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(Circle().fill(Color.green))
            .overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: 2))
            .shadow(color: .black.opacity(0.5), radius: 3)
            .padding(10)
    }
}

private struct WatchedBadgeModifier: ViewModifier {
    @EnvironmentObject private var watched: WatchedStore
    let item: MetaItem?
    let alignment: Alignment
    func body(content: Content) -> some View {
        content.overlay(alignment: alignment) {
            if let item, !item.isSeries, watched.isWatched(item) { WatchedTickBadge() }
        }
    }
}

extension View {
    /// Overlays a watched tick on a movie card when it's been marked watched.
    func watchedBadge(_ item: MetaItem?, alignment: Alignment = .topTrailing) -> some View {
        modifier(WatchedBadgeModifier(item: item, alignment: alignment))
    }
}

// MARK: - Live TV channel hold menu (Favourite / Add to Home)

/// Hold-Select on a Live TV channel: favourite it, and once it IS a favourite,
/// pin it to the home screen as well. Two steps on purpose — "Add to Home"
/// only appears on a channel you have already said you care about, which is
/// what keeps the home row short.
struct ChannelHoldMenu: ViewModifier {
    @ObservedObject private var favorites = LiveChannelFavorites.shared
    let channel: FavoriteChannel

    func body(content: Content) -> some View {
        content.contextMenu {
            let _ = HoldProbe.log("MENU BUILT — channel \(channel.name)")
            let isFavorite = favorites.isFavorite(channel.id)
            Button { favorites.toggleFavorite(channel) } label: {
                Label(isFavorite ? "Retirer des favoris" : "Favorite",
                      systemImage: isFavorite ? "star.slash" : "star")
            }
            // NO `role: .destructive` anywhere in here — tvOS refuses to
            // present a context menu that contains one (see ContinueHoldMenu).
            if isFavorite {
                Button { favorites.toggleOnHome(channel) } label: {
                    Label(favorites.isOnHome(channel.id) ? "Retirer de l’accueil" : "Ajouter à l’accueil",
                          systemImage: favorites.isOnHome(channel.id) ? "house.slash" : "house")
                }
            }
        }
    }
}

extension View {
    /// Live TV channel hold-Select menu (Favorite / Add to Home Page).
    func channelHoldMenu(_ channel: FavoriteChannel) -> some View {
        modifier(ChannelHoldMenu(channel: channel))
    }
}

// MARK: - Continue Watching hold menu (Details / Play Manually / Restart / Remove)

struct ContinueHoldMenu: ViewModifier {
    @EnvironmentObject private var progressStore: ProgressStore
    @EnvironmentObject private var watched: WatchedStore
    let progress: WatchProgress
    let onDetails: () -> Void
    let onPlayManually: () -> Void
    let onResumeFromStart: () -> Void

    /// True for a series row, whatever type spelling a sync source used.
    private var isSeriesType: Bool {
        ["series", "tv", "show", "tvshow", "anime"].contains(progress.type.lowercased())
    }

    /// The (season, episode) this row is for, from the stored columns or — when
    /// a sync source dropped them — from a row key shaped "…:<season>:<episode>"
    /// (e.g. "tt0903747:5:6"). Only the two trailing components AFTER the show
    /// id are trusted, so an exotic "kitsu:1234:5" show id is not mistaken for
    /// season 1234.
    private var episodeCoordinates: (season: Int, episode: Int)? {
        if let season = progress.season, let episode = progress.episode {
            return (season, episode)
        }
        let prefix = progress.metaID + ":"
        guard progress.id.hasPrefix(prefix) else { return nil }
        let tail = progress.id.dropFirst(prefix.count).split(separator: ":")
        guard tail.count == 2, let season = Int(tail[0]), let episode = Int(tail[1]) else {
            return nil
        }
        return (season, episode)
    }

    /// A Continue Watching card for one specific episode (as opposed to a
    /// movie). Only episodes get the manual "Mark Episode Watched" action.
    private var isEpisode: Bool { isSeriesType && episodeCoordinates != nil }

    func body(content: Content) -> some View {
        // The stores are only used by the actions, never to build the items —
        // so the row is the whole key (see StableContextMenu).
        StableContextMenu(content: content,
                          key: "\(progress.id)|\(progress.metaID)|\(progress.type)|\(isEpisode)") {
            let _ = HoldProbe.log("MENU BUILT — CW \(progress.name)")
            Button { onPlayManually() } label: { Label("Choisir une source", systemImage: "list.and.film") }
            Button { onDetails() } label: { Label("Go to Details", systemImage: "info.circle") }
            if isEpisode {
                Button { markEpisodeWatched() } label: {
                    Label("Marquer l’épisode comme vu", systemImage: "checkmark.circle")
                }
            }
            Button { onResumeFromStart() } label: { Label("Start Over", systemImage: "gobackward") }
            // NO `role: .destructive` — tvOS will not present a context menu
            // that contains one, so this single item silently killed the whole
            // Continue Watching menu while the role-free poster menu worked.
            // The wording and the ✗ glyph carry the meaning instead.
            Button {
                // Remove the whole show (all episodes), like Netflix/Hulu.
                progressStore.removeShow(metaID: progress.metaID, notifyTrakt: true)
            } label: {
                Label("Retirer des titres à reprendre", systemImage: "xmark")
            }
        }
        .equatable()
    }

    /// Mark ONLY this episode watched through the same progress/watch-history
    /// path the player uses when an episode finishes: the progress row is
    /// retired (so Continue Watching stops offering it) and the episode is
    /// recorded in watch history, which lets Home's existing Next Up logic
    /// advance the card to the following episode. Every other episode's resume
    /// position is untouched, and no season/series mark is written.
    private func markEpisodeWatched() {
        guard let (season, episode) = episodeCoordinates else { return }
        let meta = MetaItem(
            id: progress.metaID,
            type: "series",
            name: progress.name,
            poster: progress.poster,
            background: progress.background,
            logo: progress.logo
        )
        let video = MetaVideo(
            id: progress.id,
            title: progress.episodeTitle ?? progress.name,
            season: season,
            episode: episode,
            thumbnail: progress.episodeThumbnail
        )
        // Record the watch FIRST, as a user action (not `fromPlayback`). The
        // player's `onFinished` marks the same key with `fromPlayback: true`,
        // which flags it as "already reported by the stop scrobble" and makes
        // the Trakt push SKIP the history add — correct for a finished
        // playback, wrong for a manual mark that has no scrobble behind it.
        // Doing it here, before `markFinished` can set that flag, sends the
        // watched state to Trakt/SIMKL immediately. `mark` is idempotent.
        if !watched.isWatched(contentID: progress.metaID, season: season, episode: episode) {
            watched.mark(meta: meta, video: video)
        }
        // `markFinished` then retires the progress row and clears the account /
        // Stremio resume point, through the same path in-app playback uses.
        progressStore.markFinished(meta: meta, video: video)
    }
}

extension View {
    /// Continue-Watching hold-Select menu, shared across every theme.
    func continueHoldMenu(_ progress: WatchProgress,
                          onDetails: @escaping () -> Void,
                          onPlayManually: @escaping () -> Void,
                          onResumeFromStart: @escaping () -> Void) -> some View {
        modifier(ContinueHoldMenu(progress: progress, onDetails: onDetails,
                                  onPlayManually: onPlayManually,
                                  onResumeFromStart: onResumeFromStart))
    }
}
