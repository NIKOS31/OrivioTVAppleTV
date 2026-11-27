import SwiftUI

struct NTVReleaseNotes: Sendable {
    static let seenBuildKey = "ntv.releaseNotes.lastSeenBuild"
    let build: String
    let improvements: [String]
    let checks: [String]

    // Keep this entry and the app/extension build number together at release.
    static let current = NTVReleaseNotes(build: "59", improvements: [
        "Version alternative de la 58, qui reste la version de secours.",
        "Films et Séries : la page défile comme sur l’Accueil quand tu changes de rangée ou remontes vers Voir la fiche. Elle ne repart plus en arrière au milieu d’un mouvement.",
        "Refonte visuelle. Boutons : fini les bulles grises. Au repos, un bouton n’est plus que son icône et son texte posés sur l’image ; l’action principale (Regarder, Voir la fiche) porte un contour blanc. Sélectionné, il devient une pilule blanche pleine, plus grande, avec une ombre. Les boutons ronds des fiches et les filtres des sources suivent la même règle.",
        "Refonte visuelle. Affiches : plus grandes, un peu plus de six par rangée au lieu de sept, sans texte au repos : seule l’affiche sélectionnée montre son titre dessous, comme sur l’app Apple TV. Elle se soulève nettement avec une ombre au lieu d’être entourée de blanc. Les titres de rangée sont plus grands et plus gras. Avec Réduire les animations, le contour blanc revient.",
        "Refonte visuelle. Menu latéral : fermé, les icônes flottent dans une pilule sombre posée sur l’image. Ouvert, plus de panneau gris : les libellés apparaissent sur un fondu noir profond, l’entrée sélectionnée est une pilule blanche, la section ouverte est marquée d’un point.",
        "Menu latéral : les icônes et le logo restent en place à l’ouverture ; seuls les libellés apparaissent à côté, en fondu. Ouvrir ou fermer le menu n’anime plus toute la page derrière lui.",
        "Recommandations : un titre sur une ligne se place juste au-dessus de son année, sans grand vide entre les deux.",
        "Refonte visuelle. Sources : plus de cartes grises. La qualité (1080p, 720p…) devient un grand titre de groupe, chaque source une ligne aérée avec sa taille et son nom ; la source sélectionnée devient une pilule blanche avec le texte sombre. Le nom de l’addon n’est plus en majuscules et le filtre sélectionné est entouré.",
        "Refonte visuelle. Films et Séries : le titre de la page reste fixé en haut. Quand la présentation a défilé, ce bandeau affiche aussi le titre, l’année et les genres de l’affiche sélectionnée. Catégories se place en haut à droite de la présentation.",
        "Reprend tout le contenu de la 58 : inclinaison des cartes désactivée par défaut, Haut depuis la première rangée vers Voir la fiche."
    ], checks: [
        "Films et Séries : faire plusieurs Haut/Bas entre les rangées, lentement puis vite. La page doit suivre la sélection sans saut ni retour en arrière, comme sur l’Accueil.",
        "Ouvrir et fermer le menu latéral plusieurs fois : les icônes ne doivent pas bouger, les libellés apparaître en douceur, la page derrière rester immobile.",
        "Parcourir les boutons d’une fiche puis Voir la fiche et Catégories : le bouton sélectionné doit se distinguer nettement des autres depuis le canapé, et les boutons au repos rester lisibles sur l’image.",
        "Parcourir une rangée d’affiches : l’affiche sélectionnée doit se repérer d’un coup d’œil sans contour, et la navigation rester fluide avec des affiches plus grandes.",
        "Depuis la première rangée de Films : Haut doit mener à Voir la fiche, puis Haut à Catégories.",
        "Sources : parcourir la liste ; la source sélectionnée doit ressortir nettement et les autres rester lisibles sans carte.",
        "Films et Séries : descendre de deux rangées ; le bandeau du haut doit afficher le titre sélectionné sans que rien ne bouge en dessous."
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
