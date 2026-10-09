import SwiftUI

/// Both kinds of live content remain reachable when no TV addon is installed.
/// Only the selected browser is mounted, so its tasks stop on section changes.
struct NTVLiveHub: View {
    private enum Section: String, CaseIterable { case television = "Télévision", twitch = "Twitch" }
    @EnvironmentObject private var profiles: ProfileStore
    @EnvironmentObject private var account: OrivioAccountManager
    @State private var section: Section = .television
    @FocusState private var sectionFocus: Section?
    let onSelectChannel: (MetaItem) -> Void
    let onPlayDirect: (LiveChannel) -> Void
    let onBackAtRoot: () -> Void

    private var scope: String { "\(account.currentUserID ?? "local").profile.\(profiles.activeProfileID)" }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 28) {
                Text("TV en direct")
                    .font(.system(size: 38, weight: .semibold))
                    .accessibilityIdentifier("ntv.live.hub.heading")
                Spacer(minLength: 20)
                ForEach(Section.allCases, id: \.self) { choice in
                    Button { section = choice } label: {
                        HStack(spacing: 10) {
                            Label(choice.rawValue, systemImage: choice == .television ? "tv" : "bubble.left.and.bubble.right")
                            if choice == section { Image(systemName: "checkmark.circle.fill") }
                        }
                    }
                    .buttonStyle(NTVActionButtonStyle())
                    .focused($sectionFocus, equals: choice)
                    .accessibilityLabel(choice.rawValue)
                    .accessibilityValue(choice == section ? "Sélectionné" : "")
                    .accessibilityIdentifier(choice == .television ? "ntv.live.section.television" : "ntv.live.section.twitch")
                }
            }
            .padding(.horizontal, NTVViewport.horizontalInset)
            .padding(.top, 28)
            .focusSection()

            switch section {
            case .television:
                LiveTVView(onSelectChannel: onSelectChannel, onPlayDirect: onPlayDirect, showsHeading: false)
            case .twitch:
                NTVTwitchView(embedded: true) { returnToTelevision() }
            }
        }
        .foregroundStyle(NTVDesign.textPrimary)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(NTVDesign.background.ignoresSafeArea())
        .defaultFocus($sectionFocus, .television)
        .onAppear { if sectionFocus == nil { sectionFocus = section } }
        .onChange(of: scope) { _, _ in returnToTelevision() }
        .onExitCommand {
            if section == .twitch { returnToTelevision() }
            else { onBackAtRoot() }
        }
    }

    private func returnToTelevision() {
        section = .television
        sectionFocus = .television
    }
}
