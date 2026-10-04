import SwiftUI

/// A direct rail destination over the existing per-profile AddonManager.
/// Installation, sync and all advanced tools remain owned by upstream.
struct NTVAddonsView: View {
    @EnvironmentObject private var addons: AddonManager
    let onBackAtRoot: () -> Void
    @FocusState private var focusedAction: String?
    @State private var presentation: Presentation?
    @State private var lastPresentationAction = "phone"
    @State private var pendingRemoval: InstalledAddon?

    private enum Presentation: String, Identifiable {
        case phone, management
        var id: String { rawValue }
    }

    var body: some View {
        ZStack {
            ATVBackground()
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 26) {
                    Text("Addons")
                        .font(.system(size: 38, weight: .semibold))
                        .accessibilityIdentifier("ntv.addons.heading")
                    Text("Vos addons fournissent les catalogues, les affiches et les sources de lecture.")
                        .font(.system(size: 23))
                        .foregroundStyle(NTVDesign.textSecondary)

                    HStack(spacing: 24) {
                        Button { open(.phone) } label: {
                            Label("Ajouter avec mon téléphone", systemImage: "qrcode")
                        }
                        .buttonStyle(NTVActionButtonStyle())
                        .focused($focusedAction, equals: "phone")
                        .accessibilityIdentifier("ntv.addons.phone")

                        Button { open(.management) } label: {
                            Label("Gestion avancée", systemImage: "slider.horizontal.3")
                        }
                        .buttonStyle(NTVActionButtonStyle())
                        .focused($focusedAction, equals: "management")
                        .accessibilityIdentifier("ntv.addons.manage")
                    }
                    .focusSection()

                    Text("Installés")
                        .font(.system(size: 28, weight: .semibold))
                        .padding(.top, 10)

                    if addons.addons.isEmpty {
                        Text("Aucun addon installé. Ajoutez le lien de votre addon depuis votre téléphone ou dans Gestion avancée.")
                            .font(.system(size: 23))
                            .foregroundStyle(NTVDesign.textSecondary)
                    } else {
                        LazyVStack(spacing: 16) {
                            ForEach(Array(addons.addons.enumerated()), id: \.element.id) { index, addon in
                                Button {
                                    addons.setEnabled(addon, !addon.enabled)
                                } label: {
                                    NTVAddonLabel(addon: addon)
                                }
                                .buttonStyle(PlainCardButtonStyle())
                                .focused($focusedAction, equals: "row.\(index)")
                                // Use an index, never a configured URL that may contain a token.
                                .accessibilityIdentifier("ntv.addon.row.\(index)")
                                .accessibilityLabel(addon.manifest.name)
                                .accessibilityValue(addon.enabled ? "Activé" : "Désactivé")
                                .contextMenu {
                                    Button("Monter", systemImage: "arrow.up") { addons.moveUp(addon) }
                                    Button("Descendre", systemImage: "arrow.down") { addons.moveDown(addon) }
                                    if addon.manifestURL != AddonManager.cinemetaURL {
                                        Button("Retirer", systemImage: "trash", role: .destructive) {
                                            pendingRemoval = addon
                                        }
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: 1200)
                        Text("Sélectionnez un addon pour l’activer ou le désactiver. Maintenez la sélection pour changer son ordre ou le retirer.")
                            .font(.system(size: 20))
                            .foregroundStyle(NTVDesign.textSecondary)
                            .frame(maxWidth: 1200, alignment: .leading)
                    }
                }
                .foregroundStyle(NTVDesign.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, OrivioSpacing.huge)
                .padding(.top, OrivioSpacing.xl)
                .padding(.bottom, 120)
            }
            .scrollClipDisabled()
            .defaultFocus($focusedAction, "phone")
        }
        .onExitCommand(perform: onBackAtRoot)
        .fullScreenCover(item: $presentation, onDismiss: {
            focusedAction = lastPresentationAction
        }) { destination in
            switch destination {
            case .phone:
                AddonPhoneAddView(addonManager: addons, localizedForNTV: true) {
                    presentation = nil
                }
            case .management:
                ZStack {
                    ATVBackground()
                    AddonsManagementView()
                        .padding(.horizontal, OrivioSpacing.huge)
                        .padding(.vertical, OrivioSpacing.xl)
                        .accessibilityIdentifier("ntv.addons.manage.screen")
                }
                .onExitCommand { presentation = nil }
            }
        }
        .alert("Retirer cet addon ?",
            isPresented: Binding(get: { pendingRemoval != nil },
                set: { if !$0 { pendingRemoval = nil } }),
            presenting: pendingRemoval) { addon in
                Button("Retirer", role: .destructive) {
                    addons.remove(addon)
                    pendingRemoval = nil
                    focusedAction = "phone"
                }
                Button("Annuler", role: .cancel) { pendingRemoval = nil }
            } message: { addon in
                Text("\(addon.manifest.name) sera retiré de ce profil et de votre compte synchronisé. Vous pourrez le réinstaller avec son lien.")
            }
    }

    private func open(_ destination: Presentation) {
        lastPresentationAction = destination.rawValue
        presentation = destination
    }
}

private struct NTVAddonLabel: View {
    @Environment(\.isFocused) private var focused
    let addon: InstalledAddon

    private var capabilities: String {
        var parts: [String] = []
        if addon.manifest.providesCatalogs { parts.append("Catalogues") }
        if addon.manifest.providesStreams { parts.append("Sources") }
        if addon.manifest.providesMeta { parts.append("Métadonnées") }
        if addon.manifest.providesSubtitles { parts.append("Sous-titres") }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 24) {
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(NTVDesign.raised)
                if let logo = addon.manifest.logo, !logo.isEmpty {
                    RemoteImage(url: logo, contentMode: .fit, maxDimension: 72)
                        .padding(8)
                } else {
                    Image(systemName: "puzzlepiece.extension")
                        .font(.system(size: 28))
                        .foregroundStyle(NTVDesign.textSecondary)
                }
            }
            .frame(width: 72, height: 72)
            VStack(alignment: .leading, spacing: 8) {
                Text(addon.manifest.name)
                    .font(.system(size: 26, weight: .semibold))
                    .lineLimit(1)
                if !capabilities.isEmpty {
                    Text(capabilities)
                        .font(.system(size: 20))
                        .foregroundStyle(NTVDesign.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 20)
            Label(addon.enabled ? "Activé" : "Désactivé",
                systemImage: addon.enabled ? "checkmark.circle.fill" : "minus.circle")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(addon.enabled ? NTVDesign.accent : NTVDesign.textSecondary)
        }
        .foregroundStyle(NTVDesign.textPrimary)
        .padding(22)
        .background(NTVDesign.surface, in: RoundedRectangle(cornerRadius: NTVDesign.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: NTVDesign.cardRadius)
            .strokeBorder(focused ? NTVDesign.accent : .clear, lineWidth: 3))
        .focusLift(NTVDesign.controlFocusScale, focused)
        .opacity(addon.enabled ? 1 : 0.7)
    }
}
