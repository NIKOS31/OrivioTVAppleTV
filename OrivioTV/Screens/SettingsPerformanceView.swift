import SwiftUI

/// Settings → Performance: per-effect switches so slower Apple TVs (HD,
/// 4K 1st gen) can turn off exactly the things causing lag — each row says
/// what the effect costs and what OFF looks like. All ON = the full look.
struct PerformanceSettingsDetail: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var playerStore: PlayerSettingsStore
    @ObservedObject private var store = PerformanceSettingsStore.shared

    private var s: Binding<PerformanceSettingsStore.Settings> {
        Binding(get: { store.settings }, set: { store.settings = $0 })
    }

    /// Master switch: ON = every effect off (lightest), OFF = full look.
    private var maxPerformance: Binding<Bool> {
        Binding(get: { store.isMaxPerformance }, set: { store.setMaxPerformance($0) })
    }

    var body: some View {
        DetailScaffold(title: SettingsCategory.performance.title,
                       subtitle: SettingsCategory.performance.subtitle) {

            if store.reduceMotion { reduceMotionBanner }

            SettingsGroupCard(
                title: "Configuration rapide",
                subtitle: "Réglages adaptés à cette Apple TV"
            ) {
                PerfToggleRow(
                    icon: "bolt.fill",
                    title: "Mode performances",
                    subtitle: "Désactiver les effets visuels pour alléger la navigation. Vous pouvez ensuite ajuster chaque effet séparément.",
                    isOn: maxPerformance
                )
                PerfActionRow(
                    icon: "arrow.counterclockwise",
                    title: "Rétablir les réglages recommandés",
                    subtitle: "Rétablir les réglages adaptés à \(PerformanceProfile.tierLabel).",
                    action: { store.resetToRecommended() }
                )
            }

            SettingsGroupCard(
                title: "Illustration de l’accueil",
                subtitle: "Présentation du titre sélectionné sur l’accueil"
            ) {
                PerfToggleRow(
                    icon: "photo.tv",
                    title: "Illustration en fond",
                    subtitle: "Adapter le fond au titre sélectionné. Désactivé : utiliser un fond uni, plus léger sur les anciens appareils.",
                    isOn: s.heroBackdrop
                )
                PerfToggleRow(
                    icon: "square.stack.3d.forward.dottedline",
                    title: "Fondu des illustrations",
                    subtitle: "Afficher un fondu lorsque le titre change. Désactivé : changer le fond instantanément pour alléger la navigation.",
                    isOn: s.heroCrossfade
                )
            }

            SettingsGroupCard(
                title: "Cartes et rangées",
                subtitle: "Affichage des affiches et des rangées"
            ) {
                PerfToggleRow(
                    icon: "rectangle.fill.on.rectangle.fill",
                    title: "Ombres des cartes",
                    subtitle: "Afficher des ombres sous les cartes. Désactivez-les pour alléger le défilement.",
                    isOn: s.cardShadows
                )
                PerfToggleRow(
                    icon: "arrow.up.left.and.arrow.down.right",
                    title: "Zoom de sélection",
                    subtitle: "Agrandir légèrement la carte sélectionnée",
                    isOn: s.focusZoom
                )
                // No longer gated on `theme.isAppleTVTheme`: that flag is a
                // retired stub that always returns false, so this row never
                // rendered — yet `cardParallax` still drives the card button
                // style and the Performance-mode summary. Apple TV HD users
                // (where the migration forces it off) were stuck on the flat
                // card style with no switch to turn it back on, and switching
                // every VISIBLE effect off still reported Performance mode as
                // OFF because of this hidden flag.
                PerfToggleRow(
                    icon: "move.3d",
                    title: "Inclinaison des cartes",
                    subtitle: "Incliner la carte avec le pavé tactile. Cet effet est plus coûteux sur les anciens appareils.",
                    isOn: s.cardParallax
                )
            }

            SettingsGroupCard(
                title: "Animations",
                subtitle: "Mouvements de l’interface"
            ) {
                PerfToggleRow(
                    icon: "sidebar.left",
                    title: "Animation du menu",
                    subtitle: "Animer l’ouverture et la fermeture du menu",
                    isOn: s.sidebarAnimation
                )
                PerfToggleRow(
                    icon: "hand.tap",
                    title: "Animation des boutons",
                    subtitle: "Animer les boutons lorsqu’ils sont sélectionnés ou activés",
                    isOn: s.buttonAnimations
                )
            }

            SettingsGroupCard(
                title: "Chargement des images",
                subtitle: "Affichage des images à leur arrivée"
            ) {
                PerfToggleRow(
                    icon: "square.and.arrow.down.on.square",
                    title: "Précharger les affiches",
                    subtitle: "Charger les affiches des rangées suivantes à l’avance. Désactivé : les charger à leur apparition.",
                    isOn: s.artworkPrefetch
                )
                PerfToggleRow(
                    icon: "circle.lefthalf.filled",
                    title: "Fondu au chargement des images",
                    subtitle: "Afficher les images avec un fondu au lieu de les faire apparaître instantanément",
                    isOn: s.artworkFadeIn
                )
            }

            SettingsGroupCard(
                title: "Collections",
                subtitle: "Images des dossiers de collections"
            ) {
                OrivioDropdown(
                    title: "Illustration du dossier sélectionné",
                    subtitle: store.settings.collectionGifQuality.summary,
                    icon: "sparkles.tv",
                    selection: store.settings.collectionGifQuality.rawValue,
                    options: CollectionGifQuality.allCases.map {
                        OrivioDropdownOption($0.rawValue, $0.displayName)
                    }
                ) { raw in
                    store.settings.collectionGifQuality =
                        CollectionGifQuality(rawValue: raw) ?? .deviceDefault
                }
            }

            SettingsGroupCard(
                title: "Diagnostic avancé",
                subtitle: "Options de diagnostic, désactivées par défaut"
            ) {
                PerfToggleRow(
                    icon: "speedometer",
                    title: "Afficher la cadence d’images",
                    subtitle: "Afficher la cadence pendant la navigation pour observer la fluidité",
                    isOn: s.showFPSOverlay
                )

                PerfToggleRow(
                    icon: "hand.tap",
                    title: "Diagnostic de l’appui long",
                    subtitle: "Afficher les étapes de reconnaissance de l’appui long pour diagnostiquer les menus",
                    isOn: s.showHoldProbe
                )

                PerfToggleRow(
                    icon: "waveform.path.ecg",
                    title: "Diagnostic pendant la lecture",
                    subtitle: "Afficher cadence, images perdues, décalage audio, débit et tampon pendant la lecture",
                    isOn: s.showPlayerDiagnostics
                )

                // Lived under Playback → Seeking; it's a diagnostic overlay, so
                // it belongs with the other two.
                PerfToggleRow(
                    icon: "photo.stack",
                    title: "Aperçus sur la barre de lecture",
                    subtitle: "Préparer les images d’aperçu pour parcourir la vidéo. Désactivez cette option si elle gêne la fluidité.",
                    isOn: Binding(get: { playerStore.settings.scrubPreviewsEnabled },
                                  set: { playerStore.settings.scrubPreviewsEnabled = $0 })
                )
                PerfToggleRow(
                    icon: "ladybug.fill",
                    title: "Diagnostic de la télécommande",
                    subtitle: "Afficher les derniers gestes et boutons reçus par le lecteur",
                    isOn: Binding(get: { playerStore.settings.showInputDebug },
                                  set: { playerStore.settings.showInputDebug = $0 })
                )

                // The one switch that makes everything else diagnosable on a
                // Release/sideloaded build. Turn it on, reproduce the problem,
                // then pull the log with scripts/record.sh (or probe.sh).
                PerfToggleRow(
                    icon: "dot.radiowaves.left.and.right",
                    title: "Partager les diagnostics sur le réseau local",
                    subtitle: "Enregistrer les événements de navigation et de lecture et les rendre accessibles sur votre réseau local. Désactivé par défaut.",
                    isOn: Binding(
                        get: { ProbeGate.isEnabled },
                        set: { on in
                            UserDefaults.standard.set(on, forKey: ProbeGate.defaultsKey)
                            ProbeGate.set(on)
                            if on { ColorProbeServer.shared.start() }
                            else { ColorProbeServer.shared.stop() }
                        }
                    )
                )
            }

            Text("Ajustez les effets pour trouver la fluidité qui vous convient. Ces réglages sont propres à cette TV.")
                .font(.system(size: 18))
                .foregroundStyle(theme.palette.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Shown when the system Accessibility → Reduce Motion switch is on: the
    /// motion effects are forced off no matter what the switches below say.
    private var reduceMotionBanner: some View {
        HStack(spacing: OrivioSpacing.md) {
            SettingsIconTile(symbol: "figure.walk.motion")
            VStack(alignment: .leading, spacing: 4) {
                Text("Réduire les animations est activé")
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(theme.palette.textPrimary)
                Text("Le réglage d’accessibilité de la TV désactive les effets de mouvement, quels que soient les choix ci-dessous.")
                    .font(.system(size: 19))
                    .foregroundStyle(theme.palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(OrivioSpacing.lg)
        .background(
            RoundedRectangle(cornerRadius: theme.settingsCardRadius, style: .continuous)
                .fill(theme.palette.secondary.opacity(0.14))
        )
        .overlay(
            RoundedRectangle(cornerRadius: theme.settingsCardRadius, style: .continuous)
                .strokeBorder(theme.palette.secondary.opacity(0.4), lineWidth: 1)
        )
    }
}

/// Toggle row matching the redesigned settings rows (icon tile, title, wrapped
/// description, switch; flat until focused).
private struct PerfToggleRow: View {
    let icon: String
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        Button { isOn.toggle() } label: {
            PerfRowLabel(icon: icon, title: title, subtitle: subtitle) {
                OrivioSwitch(isOn: isOn)
            }
        }
        .buttonStyle(PlainCardButtonStyle())
    }
}

/// A tappable action row (no switch) — used for "Reset to recommended".
private struct PerfActionRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            PerfRowLabel(icon: icon, title: title, subtitle: subtitle) {
                EmptyView()
            }
        }
        .buttonStyle(PlainCardButtonStyle())
    }
}

/// Shared row body: accent icon tile + title + wrapped description + a trailing
/// accessory (switch, or nothing). Flat until focused, matching the other
/// redesigned settings panes.
private struct PerfRowLabel<Accessory: View>: View {
    @EnvironmentObject private var theme: ThemeManager
    @Environment(\.isFocused) private var isFocused
    let icon: String
    let title: String
    let subtitle: String
    @ViewBuilder let accessory: Accessory

    var body: some View {
        HStack(alignment: .top, spacing: OrivioSpacing.md) {
            SettingsIconTile(symbol: icon)
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 25, weight: .semibold))
                    .foregroundStyle(theme.palette.textPrimary)
                Text(subtitle)
                    .font(.system(size: 20))
                    .foregroundStyle(theme.palette.textSecondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 1000, alignment: .leading)
            }
            Spacer(minLength: OrivioSpacing.lg)
            accessory
                .padding(.top, 4)
        }
        .padding(.horizontal, OrivioSpacing.md)
        .padding(.vertical, OrivioSpacing.md)
        .frame(minHeight: 76)
        .frame(maxWidth: .infinity)
        .background(SettingsRowBackground(isFocused: isFocused))
    }
}
