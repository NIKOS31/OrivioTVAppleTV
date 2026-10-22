import SwiftUI

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
    @ObservedObject var hero: HeroFocus
    @ScaledMetric(relativeTo: .title2) private var titleSize: CGFloat = 48
    @ScaledMetric(relativeTo: .callout) private var metadataSize: CGFloat = 25
    @ScaledMetric(relativeTo: .body) private var synopsisSize: CGFloat = 29

    var body: some View {
        let _ = NTVRenderProbe.evaluated(.catalogSpotlight)
        if let item = hero.item {
            HStack(alignment: .center, spacing: 30) {
                NTVSpotlightCover(item: item, width: 132, height: 198)
                VStack(alignment: .leading, spacing: 12) {
                    Text("EN SÉLECTION")
                    .font(.system(size: metadataSize, weight: .medium))
                    .foregroundStyle(NTVDesign.textSecondary)
                    Text(item.name)
                    .font(.system(size: titleSize, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    Text([item.year, item.genres?.prefix(2).map(NTVFrench.genre).joined(separator: " · ")]
                    .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.system(size: metadataSize, weight: .medium))
                    .foregroundStyle(NTVDesign.textSecondary)
                    .lineLimit(1, reservesSpace: true)
                    Text(item.description ?? "")
                    .font(.system(size: synopsisSize))
                    .foregroundStyle(NTVDesign.textSecondary)
                    .lineLimit(2, reservesSpace: true)
                }
                .frame(maxWidth: 920, alignment: .leading)
                Spacer(minLength: 0)
            }
            .foregroundStyle(NTVDesign.textPrimary)
            .frame(maxWidth: .infinity, minHeight: 224, alignment: .leading)
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
                HStack(spacing: 24) {
                    Button { onSelect(item) } label: {
                        Label("Voir la fiche", systemImage: "info.circle")
                    }
                    .buttonStyle(NTVActionButtonStyle(prominent: true, capsule: true))
                    .focused(playFocus)
                    .accessibilityIdentifier("ntv.home.spotlight")
                    .onExitCommand(perform: onBack)
                    .onChange(of: playFocus.wrappedValue) { _, focused in
                        if focused { ContentFocusRouter.shared.noteFocused(row: "home.heroPlay") }
                    }
                    if hero.spotlight.count > 1 {
                        HStack(spacing: 7) {
                            ForEach(hero.spotlight.indices, id: \.self) { index in
                                Capsule()
                                    .fill(.white.opacity(index == hero.spotlightIndex ? 0.85 : 0.25))
                                    .frame(width: index == hero.spotlightIndex ? 18 : 6, height: 4)
                            }
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Proposition \(hero.spotlightIndex + 1) sur \(hero.spotlight.count)")
                    }
                }
                .foregroundStyle(NTVDesign.textPrimary)
            }
            .foregroundStyle(NTVDesign.textPrimary)
            .frame(maxWidth: 920, minHeight: 350, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("ntv.seanime.home.feature")
        }
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

/// A non-focusable cover anchors the editorial block. Loading metadata or
/// artwork never changes its reserved geometry or adds another remote target.
private struct NTVSpotlightCover: View {
    let item: MetaItem
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        ZStack {
            NTVDesign.raised
            if let poster = item.poster, !poster.isEmpty {
                // RemoteImage converts points to display pixels itself.
                // Passing twice the height would decode redundant pixels.
                RemoteImage(url: poster, maxDimension: height)
            } else {
                Image(systemName: "film")
                    .font(.system(size: 38, weight: .medium))
                    .foregroundStyle(NTVDesign.textSecondary)
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: NTVDesign.cardRadius))
        .overlay { RoundedRectangle(cornerRadius: NTVDesign.cardRadius)
            .strokeBorder(.white.opacity(0.1), lineWidth: 1) }
        .accessibilityHidden(true)
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
