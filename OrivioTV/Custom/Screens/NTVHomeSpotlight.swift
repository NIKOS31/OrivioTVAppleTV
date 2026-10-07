import SwiftUI

/// Only this layer observes the selection. Catalog rows keep their own focus
/// and never rebuild when a settled selection changes the artwork.
struct NTVFocusBackdrop: View {
    @ObservedObject var hero: HeroFocus
    @ObservedObject private var performance = PerformanceSettingsStore.shared
    @EnvironmentObject private var canvas: NTVBackdropCanvas
    let identifier: String

    var body: some View {
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
        canvas.update(identifier, url: performance.settings.heroBackdrop ? (hero.item?.background ?? hero.item?.poster) : nil)
    }
}

struct NTVCatalogSpotlight: View {
    @ObservedObject var hero: HeroFocus

    var body: some View {
        if let item = hero.item {
            VStack(alignment: .leading, spacing: 12) {
                Text(item.name)
                    .font(.system(size: 40, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text([item.year, item.genres?.prefix(2).map(NTVFrench.genre).joined(separator: " · ")]
                    .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.system(size: 20))
                    .foregroundStyle(NTVDesign.textSecondary)
                if let description = item.description, !description.isEmpty {
                    Text(description)
                        .font(.system(size: 20))
                        .foregroundStyle(NTVDesign.textSecondary)
                        .lineLimit(2)
                }
            }
            .foregroundStyle(NTVDesign.textPrimary)
            .frame(maxWidth: 820, minHeight: 160, alignment: .leading)
        }
    }
}

/// Compact, real metadata spotlight. Observing HeroFocus here avoids rebuilding
/// the catalog rows whenever the viewer moves between posters.
struct NTVHomeSpotlight: View {
    @ObservedObject var hero: HeroFocus
    var playFocus: FocusState<Bool>.Binding
    let onSelect: (MetaItem) -> Void
    let onBack: () -> Void

    var body: some View {
        if let item = hero.item {
            ZStack(alignment: .leading) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("À découvrir")
                        .font(.system(size: 16, weight: .medium))
                        .tracking(1.5)
                        .foregroundStyle(NTVDesign.textSecondary)
                    Text(item.name)
                        .font(.system(size: 44, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Text([item.year, item.genres?.prefix(2).map(NTVFrench.genre).joined(separator: " · ")]
                        .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.system(size: 20))
                        .foregroundStyle(NTVDesign.textSecondary)
                    if let description = item.description, !description.isEmpty {
                        Text(description)
                            .font(.system(size: 20))
                            .foregroundStyle(NTVDesign.textSecondary)
                            .lineLimit(2)
                    }
                    Button { onSelect(item) } label: {
                        Label("Voir la fiche", systemImage: "info.circle")
                    }
                    .buttonStyle(NTVActionButtonStyle())
                    .focused(playFocus)
                    .accessibilityIdentifier("ntv.home.spotlight")
                    .onExitCommand(perform: onBack)
                    .onChange(of: playFocus.wrappedValue) { _, focused in
                        if focused { ContentFocusRouter.shared.noteFocused(row: "home.heroPlay") }
                    }
                }
                .foregroundStyle(NTVDesign.textPrimary)
                .frame(maxWidth: 760, alignment: .leading)
            }
            .frame(height: 310)
            .clipShape(RoundedRectangle(cornerRadius: NTVDesign.cardRadius))
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
