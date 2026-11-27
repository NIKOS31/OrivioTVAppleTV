import SwiftUI

struct NTVReleaseNotes: Sendable {
    static let seenBuildKey = "ntv.releaseNotes.lastSeenBuild"
    let build: String
    let improvements: [String]
    let checks: [String]

    // Keep this entry and the app/extension build number together at release.
    static let current = NTVReleaseNotes(build: "59", improvements: [
        "Version alternative de la 58, qui reste la version de secours.",
        "Films et Séries : changer de rangée fait glisser la page au lieu de la déplacer d’un coup. Monter vers Voir la fiche glisse aussi. Avec Réduire les animations, le déplacement reste instantané.",
        "Menu latéral : les icônes et le logo restent en place à l’ouverture ; seuls les libellés apparaissent à côté, en fondu. L’ouverture ralentit en arrivant, la fermeture est un peu plus vive.",
        "Menu latéral : un repère blanc marque la section ouverte, menu ouvert ou fermé. À l’ouverture, un voile sombre assure la lisibilité des libellés sur les affiches.",
        "Ouvrir ou fermer le menu n’anime plus toute la page derrière lui.",
        "Boutons : un seul style dans toute l’app. Au repos, une pilule translucide ; sélectionné, un blanc plein qui s’agrandit légèrement avec une ombre douce, sans second anneau. Catégories adopte la même pilule que Voir la fiche.",
        "Recommandations : un titre sur une ligne se place juste au-dessus de son année, sans grand vide entre les deux.",
        "Sources : le nom de l’addon n’est plus écrit en majuscules.",
        "Reprend tout le contenu de la 58 : inclinaison des cartes désactivée par défaut, Haut depuis la première rangée vers Voir la fiche."
    ], checks: [
        "Films et Séries : faire plusieurs Haut/Bas entre les rangées. La page doit glisser sans saut, et le compteur de cadence rester stable.",
        "Ouvrir et fermer le menu latéral plusieurs fois : les icônes ne doivent pas bouger, les libellés apparaître en douceur, la page derrière rester immobile.",
        "Vérifier le repère de la section ouverte dans le menu fermé.",
        "Parcourir les boutons d’une fiche puis Voir la fiche et Catégories : le bouton sélectionné doit se distinguer nettement des autres depuis le canapé.",
        "Depuis la première rangée de Films : Haut doit mener à Voir la fiche, puis Haut à Catégories."
    ])

    func shouldPresent(installedBuild: String, seenBuild: String, arguments: [String] = []) -> Bool {
        #if DEBUG
        if !arguments.contains("-ntvReleaseNotesDemo"), arguments.contains(where: {
            $0.localizedCaseInsensitiveContains("demo") || $0.contains("Probe") || $0 == "-ntvLaunchTest"
        }) { return false }
        #endif
        return installedBuild == build && seenBuild != build
    }
}

struct NTVReleaseNotesPresentation: ViewModifier {
    let eligible: Bool
    @Binding var isPresented: Bool
    let onDismiss: () -> Void
    @AppStorage(NTVReleaseNotes.seenBuildKey) private var seenBuild = ""

    private var installedBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
    }

    func body(content: Content) -> some View {
        content
            .task(id: eligible) {
                guard eligible, NTVReleaseNotes.current.shouldPresent(
                    installedBuild: installedBuild, seenBuild: seenBuild,
                    arguments: ProcessInfo.processInfo.arguments) else { return }
                // Let the welcome/profile cover finish dismissing first.
                do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
                guard !Task.isCancelled else { return }
                isPresented = true
            }
            .fullScreenCover(isPresented: $isPresented, onDismiss: onDismiss) {
                NTVReleaseNotesView(notes: .current) {
                    seenBuild = installedBuild
                    isPresented = false
                }
                .interactiveDismissDisabled()
            }
    }
}

struct NTVReleaseNotesView: View {
    let notes: NTVReleaseNotes
    let onContinue: () -> Void
    @FocusState private var continueFocused: Bool

    var body: some View {
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: 24) {
                Text("Nouveautés de nTV \(notes.build)")
                    .font(.system(size: 42, weight: .bold))
                    .accessibilityAddTraits(.isHeader)
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        section("Améliorations", lines: notes.improvements)
                        section("À vérifier sur ton Apple TV", lines: notes.checks)
                        Text("Les tests automatiques ne remplacent pas ton essai de fluidité sur la TV.")
                            .font(.system(size: 23))
                            .foregroundStyle(NTVDesign.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
                }
                .focusable()
                .accessibilityIdentifier("ntv.releaseNotes.content")
                Button("Continuer", action: onContinue)
                    .buttonStyle(NTVActionButtonStyle())
                    .focused($continueFocused)
                    .accessibilityIdentifier("ntv.releaseNotes.continue")
            }
            .padding(48)
            .frame(width: min(980, max(0, geometry.size.width - 120)),
                   height: min(820, max(0, geometry.size.height - 100)), alignment: .topLeading)
            .background(NTVDesign.surface, in: RoundedRectangle(cornerRadius: 24))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(NTVDesign.background.ignoresSafeArea())
        .foregroundStyle(NTVDesign.textPrimary)
        .onAppear { continueFocused = true }
        .onExitCommand(perform: onContinue)
    }

    private func section(_ title: String, lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.system(size: 29, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            ForEach(lines, id: \.self) { line in
                Text(line).font(.system(size: 25)).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
