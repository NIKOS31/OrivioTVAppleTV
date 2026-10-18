import SwiftUI

/// Both kinds of live content remain reachable when no TV addon is installed.
/// Only the selected browser is mounted, so its tasks stop on section changes.
struct NTVLiveHub: View {
    private enum Section: String, CaseIterable { case television = "Télévision", twitch = "Twitch" }
    @EnvironmentObject private var profiles: ProfileStore
    @EnvironmentObject private var account: OrivioAccountManager
    @State private var section: Section = .television
    @State private var selectorRevision = 0
    @FocusState private var sectionFocus: Section?
    @ScaledMetric(relativeTo: .body) private var selectorLabelSize: CGFloat = 23
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
                    .ntvHalloweenDecor(.heading)
                Spacer(minLength: 20)
                HStack(spacing: 0) {
                    ForEach(Section.allCases, id: \.self) { choice in
                        Button { section = choice } label: {
                            Label(choice == .television ? "TV" : "Twitch",
                                  systemImage: choice == .television ? "tv" : "bubble.left.and.bubble.right")
                                .font(.system(size: selectorLabelSize, weight: .semibold))
                                .lineLimit(1)
                                .frame(width: 144, height: 52)
                                .foregroundStyle(choice == section ? NTVDesign.background : NTVDesign.textPrimary)
                                .background {
                                    Capsule().fill(choice == section ? NTVDesign.textPrimary : .clear)
                                }
                                .overlay {
                                    Capsule().inset(by: -4)
                                        .strokeBorder(sectionFocus == choice ? .white : .clear, lineWidth: 2)
                                }
                        }
                        .buttonStyle(PlainCardButtonStyle())
                        .focused($sectionFocus, equals: choice)
                        .accessibilityLabel(choice.rawValue)
                        .accessibilityValue(choice == section ? "Sélectionné" : "")
                        .accessibilityAddTraits(choice == section ? .isSelected : [])
                        .accessibilityIdentifier(choice == .television ? "ntv.live.section.television" : "ntv.live.section.twitch")
                    }
                }
                .padding(4)
                .background(NTVDesign.surface, in: Capsule())
                .overlay { Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 1) }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Type de direct")
            }
            .padding(.horizontal, NTVViewport.horizontalInset)
            .padding(.top, 28)
            .focusSection()
            .id(selectorRevision)
            .onAppear {
                if section == .television { sectionFocus = .television }
            }

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
        .onChange(of: scope) { _, _ in returnToTelevision() }
        .onExitCommand {
            if section == .twitch { returnToTelevision() }
            else { onBackAtRoot() }
        }
    }

    private func returnToTelevision() {
        section = .television
        // Recreate only the two selectors when retiring the embedded browser.
        // Their new focus items can use normal directional navigation instead
        // of keeping references to the removed browser's focus hierarchy.
        sectionFocus = nil
        selectorRevision += 1
    }
}
