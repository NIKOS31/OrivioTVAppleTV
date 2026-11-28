import SwiftUI

struct NTVReleaseNotes: Sendable {
    static let seenBuildKey = "ntv.releaseNotes.lastSeenBuild"
    let build: String
    let improvements: [String]
    let checks: [String]

    // Keep this entry and the app/extension build number together at release.
    static let current = NTVReleaseNotes(build: "59", improvements: [
        "Version alternative de la 58, qui reste la version de secours.",
        "Nouveau look : boutons sans bulles grises, la sélection devient une pilule blanche partout.",
        "Affiches plus grandes, soulevées sans cadre ; seul le titre de l’affiche sélectionnée s’affiche.",
        "Films et Séries : défilement fluide sans saut, bandeau fixe en haut avec Catégories et le titre sélectionné.",
        "Depuis Catégories, Bas mène à Voir la fiche (petite pilule grise), puis à la première rangée.",
        "Recherche : rangées Séries, Films et Animés en haut de l’écran ; les animés ne sont plus cachés.",
        "Lecteur : Passer l’intro toujours accessible, temps restant non sélectionnable, barre plus calme.",
        "Sources, Réglages, Bibliothèque et Addons : listes aérées, textes plus grands, plus de cartes grises.",
        "Menu latéral : pilule flottante fermée, libellés en fondu à l’ouverture, page immobile derrière.",
        "Décor de Noël du 20 novembre au 6 janvier, avec le traîneau du Père Noël ; neige en option dans Réglages › Apparence.",
        "Reprend la 58 : inclinaison des cartes désactivée par défaut, Haut depuis la première rangée vers Voir la fiche."
    ], checks: [
        "Films et Séries : Haut/Bas lents puis rapides ; la page suit la sélection sans saut.",
        "Depuis Catégories : Bas mène à Voir la fiche, puis à la première rangée.",
        "Recherche : une série et un animé apparaissent en haut, chacun dans sa rangée.",
        "Lecteur pendant un générique : Haut depuis la barre sélectionne Passer l’intro.",
        "Réglages : le défilement reste fluide et chaque texte se lit du canapé.",
        "Neige activée : elle reste derrière les affiches et l’Accueil reste fluide."
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
