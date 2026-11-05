import SwiftUI

struct NTVReleaseNotes: Sendable {
    static let seenBuildKey = "ntv.releaseNotes.lastSeenBuild"
    let build: String
    let improvements: [String]
    let checks: [String]

    // Keep this entry and the app/extension build number together at release.
    static let current = NTVReleaseNotes(build: "52", improvements: [
        "Les cartes d’épisodes laissent davantage d’espace à leur voisin pendant l’agrandissement au focus.",
        "Les rangées d’affiches nTV de l’Accueil, des Films et des Séries sont davantage espacées.",
        "Films et Séries : les changements de rangée limitent le défilement au nécessaire pour conserver les repères à l’écran."
    ], checks: [
        "Animés ou série : focaliser le premier épisode puis un épisode au milieu. Les images doivent rester séparées et leurs textes lisibles.",
        "Films et Séries : parcourir plusieurs affiches et changer de rangée. Vérifier la séparation des cartes, puis signaler tout saut vertical inattendu.",
        "Comparer les changements de rangée par appuis et par balayages. Les baisses de fluidité restent à diagnostiquer : relever UI Hz, max ms et retards pendant les mouvements puis après 10 secondes immobile.",
        "Lecteur : confirmer que l’aperçu reste disponible entre deux glissements, que Retour annule et qu’OK valide."
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
