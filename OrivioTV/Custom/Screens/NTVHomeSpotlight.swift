import SwiftUI

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
                GeometryReader { geometry in
                    RemoteImage(url: item.background ?? item.poster,
                                maxDimension: geometry.size.width)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                }
                LinearGradient(colors: [NTVDesign.surface, NTVDesign.surface.opacity(0.94),
                                         NTVDesign.surface.opacity(0.15)],
                               startPoint: .leading, endPoint: .trailing)
                VStack(alignment: .leading, spacing: 14) {
                    Text(item.name)
                        .font(.system(size: 36, weight: .semibold))
                        .lineLimit(1)
                    Text([item.year, item.genres?.prefix(2).joined(separator: " · ")]
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
                .frame(maxWidth: 850, alignment: .leading)
                .padding(28)
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
