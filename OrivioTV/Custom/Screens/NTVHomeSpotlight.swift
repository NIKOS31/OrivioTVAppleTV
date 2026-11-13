import SwiftUI
import Combine

/// Only this layer observes the selection. Catalog rows keep their own focus
/// and never rebuild when a settled selection changes the artwork.
struct NTVFocusBackdrop: View {
    @ObservedObject var hero: HeroFocus
    @ObservedObject private var performance = PerformanceSettingsStore.shared
    @Environment(\.ntvBackdropCanvas) private var canvas
    let identifier: String

    var body: some View {
        let _ = NTVRenderProbe.evaluated(.focusBackdrop)
        Color.clear
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Fond du titre sélectionné")
        .accessibilityValue(hero.item?.id ?? "")
        .accessibilityIdentifier(identifier)
        .onAppear { reportArtwork() }
        .onChange(of: hero.item?.id) { _, _ in reportArtwork() }
        .onChange(of: hero.item?.background) { _, _ in reportArtwork() }
        .onChange(of: hero.item?.poster) { _, _ in reportArtwork() }
        .onChange(of: performance.settings.heroBackdrop) { _, _ in reportArtwork() }
    }

    private func reportArtwork() {
        canvas?.update(identifier, url: performance.settings.heroBackdrop ? (hero.item?.background ?? hero.item?.poster) : nil)
    }
}

struct NTVCatalogSpotlight: View {
    @EnvironmentObject private var settings: HomeCatalogSettingsStore
    @EnvironmentObject private var profiles: ProfileStore
    @EnvironmentObject private var addons: AddonManager
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var model: NTVCatalogShelfModel
    let hero: HeroFocus
    var focus: FocusState<Bool>.Binding
    let mediaType: String
    let active: Bool
    let onSelect: (MetaItem) -> Void
    let onBack: () -> Void
    let onMove: (MoveCommandDirection) -> Void
    @State private var hasRecommendations = false
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private struct Inputs: Hashable {
        let items: [MetaItem]
        let scope: String
        let hideUnreleased: Bool
        let hideUnavailable: Bool
    }
    private var inputs: Inputs {
        Inputs(items: model.items,
            scope: NTVSourceAvailabilityStore.scope(profile: profiles.activeProfileID,
                addons: addons.addons.filter(\.enabled)),
            hideUnreleased: settings.hideUnreleasedContent, hideUnavailable: settings.hideUnavailableSources)
    }

    var body: some View {
        let _ = NTVRenderProbe.evaluated(.catalogSpotlight)
        Group {
            if hasRecommendations {
                NTVHomeSpotlight(hero: hero, playFocus: focus, onSelect: onSelect, onBack: onBack,
                    identifier: "ntv.catalog.\(mediaType).spotlight",
                    routerID: "ntv.catalog.\(mediaType).spotlight",
                    featureIdentifier: "ntv.catalog.\(mediaType).feature",
                    onFocus: { if $0 { hero.resumeSpotlight() } })
            }
        }
        .frame(minHeight: 350, alignment: .topLeading)
        .onMoveCommand { if focus.wrappedValue { onMove($0) } }
        .task(id: inputs) {
            let selection = inputs
            let absent = await NTVSourceAvailabilityStore.shared.absentUntil(for: selection.items, scope: selection.scope)
            guard !Task.isCancelled else { return }
            let visible = NTVPosterVisibility(items: selection.items,
                hideUnreleased: selection.hideUnreleased, hideUnavailable: selection.hideUnavailable,
                unavailableUntil: absent, now: Date(), isAnime: { _ in false }).items(keeping: nil)
            let illustrated = visible.filter { $0.background != nil || $0.poster != nil }
            let recommendations = Array((illustrated.isEmpty ? visible : illustrated).prefix(10))
            hero.setSpotlight(recommendations)
            hasRecommendations = !recommendations.isEmpty
        }
        .onReceive(tick) { _ in
            guard active, scenePhase == .active, hero.rolls else { return }
            hero.rotateIfIdle()
        }
    }
}

/// Compact, real metadata spotlight. Observing HeroFocus here avoids rebuilding
/// the catalog rows whenever the viewer moves between posters.
struct NTVHomeSpotlight: View {
    @ObservedObject var hero: HeroFocus
    @ScaledMetric(relativeTo: .title2) private var titleSize: CGFloat = 48
    @ScaledMetric(relativeTo: .callout) private var metadataSize: CGFloat = 25
    @ScaledMetric(relativeTo: .body) private var synopsisSize: CGFloat = 29
    var playFocus: FocusState<Bool>.Binding
    let onSelect: (MetaItem) -> Void
    let onBack: () -> Void
    var identifier = "ntv.home.spotlight"
    var routerID = "home.heroPlay"
    var featureIdentifier = "ntv.seanime.home.feature"
    var onFocus: (Bool) -> Void = { _ in }

    var body: some View {
        let _ = NTVRenderProbe.evaluated(.homeSpotlight)
        if let item = hero.item {
            VStack(alignment: .leading, spacing: 16) {
                Text(item.name)
                    .font(.system(size: titleSize, weight: .semibold))
                    .lineLimit(2, reservesSpace: true)
                    .minimumScaleFactor(0.75)
                Text([item.year, item.genres?.prefix(2).map(NTVFrench.genre).joined(separator: " · ")]
                    .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.system(size: metadataSize, weight: .medium))
                    .foregroundStyle(NTVDesign.textSecondary)
                    .lineLimit(1, reservesSpace: true)
                // Reserve text geometry even while metadata arrives.
                Text(item.description ?? "")
                    .font(.system(size: synopsisSize))
                    .foregroundStyle(NTVDesign.textSecondary)
                    .lineLimit(2, reservesSpace: true)
                NTVSpotlightAction(focus: playFocus, index: hero.spotlightIndex,
                    count: hero.spotlight.count, title: item.name, identifier: identifier,
                    onSelect: { onSelect(item) }, onStep: { hero.stepSpotlight(by: $0) }, onBack: onBack,
                    onFocus: { focused in
                        hero.heroButtonFocused = focused
                        if focused {
                            hero.markInteraction()
                            ContentFocusRouter.shared.noteFocused(row: routerID)
                        }
                        onFocus(focused)
                    })
            }
            .foregroundStyle(NTVDesign.textPrimary)
            .frame(maxWidth: 920, minHeight: 350, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(featureIdentifier)
        }
    }
}

/// Reuse the existing hero's native focus sentinels so Up/Down keep working.
struct NTVSpotlightAction: View {
    var focus: FocusState<Bool>.Binding
    let index: Int
    let count: Int
    let title: String
    let identifier: String
    let onSelect: () -> Void
    let onStep: (Int) -> Void
    let onBack: () -> Void
    var onFocus: (Bool) -> Void = { _ in }
    @FocusState private var step: Int?
    @State private var leftFocusAt: Date?

    var body: some View {
        HStack(spacing: 24) {
            HStack(spacing: 0) {
                stepTarget(-1)
                Button(action: onSelect) { Label("Voir la fiche", systemImage: "info.circle") }
                    .buttonStyle(NTVActionButtonStyle(prominent: true, capsule: true))
                    .focused(focus)
                    .accessibilityLabel("Voir la fiche de " + title)
                    .accessibilityValue(count > 1 ? "Proposition \(index + 1) sur \(count)" : "")
                    .accessibilityHint("Gauche ou droite pour changer de proposition. À la première, gauche ouvre le menu. Retour ouvre aussi le menu.")
                    .accessibilityIdentifier(identifier)
                    .onExitCommand(perform: onBack)
                if count > 1 { stepTarget(1) }
            }
            HStack(spacing: 7) {
                ForEach(0..<count, id: \.self) { value in
                    Capsule().fill(.white.opacity(value == index ? 0.85 : 0.25))
                        .frame(width: value == index ? 18 : 6, height: 4)
                }
            }
            .accessibilityHidden(true)
        }
        .foregroundStyle(NTVDesign.textPrimary)
        .onChange(of: focus.wrappedValue) { _, focused in
            if !focused { leftFocusAt = Date() }
            onFocus(focused)
        }
        .onChange(of: step) { _, direction in
            guard let direction else { return }
            let fromAction = focus.wrappedValue || leftFocusAt.map { Date().timeIntervalSince($0) < 0.35 } == true
            step = nil
            if fromAction, direction < 0, index == 0 {
                onBack()
                return
            }
            if fromAction { onStep(direction) }
            focus.wrappedValue = true
        }
    }

    private func stepTarget(_ direction: Int) -> some View {
        Color.clear.frame(width: 1, height: 44)
            .focusable().focused($step, equals: direction)
            .accessibilityHidden(true)
    }
}

/// Native visibility reports only threshold crossings, not a scroll-offset
/// state write on every frame. Older tvOS uses the lazy view's lifecycle.
struct NTVSpotlightVisibility: ViewModifier {
    let hero: HeroFocus

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(tvOS 18.0, *) {
            content
                .onScrollVisibilityChange(threshold: 0.05) { visible in
                    hero.setPresentationActive(visible)
                }
                .onDisappear { hero.setPresentationActive(false) }
        } else {
            content
                .onAppear { hero.setPresentationActive(true) }
                .onDisappear { hero.setPresentationActive(false) }
        }
    }
}

struct NTVEmptyCatalog: View {
    let message: String
    let onOpenSettings: () -> Void
    var onRetry: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Vos catalogues")
                .font(.system(size: 30, weight: .semibold))
            Text(message)
                .font(.system(size: 23))
                .foregroundStyle(NTVDesign.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 22) {
                Button(action: onOpenSettings) {
                    Label("Configurer les addons", systemImage: "puzzlepiece.extension")
                }
                .buttonStyle(NTVActionButtonStyle())
                .accessibilityIdentifier("ntv.catalog.configure")
                if let onRetry {
                    Button("Réessayer", action: onRetry)
                        .buttonStyle(NTVActionButtonStyle())
                }
            }
        }
        .foregroundStyle(NTVDesign.textPrimary)
        .padding(36)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NTVDesign.surface, in: RoundedRectangle(cornerRadius: NTVDesign.cardRadius))
    }
}
