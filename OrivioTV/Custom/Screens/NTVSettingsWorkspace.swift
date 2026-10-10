import SwiftUI

/// Categories and their detail pane scroll independently within the TV viewport.
struct NTVSettingsWorkspace: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var profiles: ProfileStore
    @EnvironmentObject private var addonManager: AddonManager
    @EnvironmentObject private var collections: CollectionsStore
    var onOpenProfiles: () -> Void = {}
    @State private var selected: SettingsCategory = .appearance
    @State private var editingProfile = false
    @FocusState private var focusedCategory: SettingsCategory?

    private var categories: [SettingsCategory] {
        SettingsCategory.allCases.filter { theme.experienceMode.isAdvanced || !$0.isAdvanced }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 24) {
                Text("Réglages")
                    .font(.system(size: 38, weight: .semibold))
                    .accessibilityIdentifier("ntv.settings.heading")
                    .ntvHalloweenDecor(.heading)
                Spacer()
                Button { editingProfile = true } label: {
                    HStack(spacing: 14) {
                        ProfileAvatarView(profile: profiles.active, size: 54)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(profiles.active.name).font(.system(size: 23, weight: .medium))
                            Text("Personnaliser mon profil").font(.system(size: 18))
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                }
                .buttonStyle(NTVActionButtonStyle())
                .accessibilityIdentifier("ntv.settings.customize")
            }

            HStack(alignment: .top, spacing: 24) {
                ScrollView(.vertical) {
                    VStack(spacing: 8) {
                        ForEach(categories) { category in
                            Button { selected = category } label: {
                                NTVSettingsCategoryLabel(category: category, selected: selected == category)
                            }
                            .buttonStyle(PlainCardButtonStyle())
                            .focused($focusedCategory, equals: category)
                            .accessibilityIdentifier("ntv.settings.category.\(category.rawValue)")
                        }
                        Button(action: onOpenProfiles) {
                            Label("Changer de profil", systemImage: "person.2")
                                .font(.system(size: 22))
                                .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
                                .padding(.horizontal, 18)
                        }
                        .buttonStyle(PlainCardButtonStyle())
                    }
                    .padding(6)
                }
                .frame(width: 288)
                .focusSection()
                .defaultFocus($focusedCategory, selected)
                .accessibilityIdentifier("ntv.settings.categories")

                SettingsCategoryPane(category: selected)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(NTVDesign.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: 22))
                    .clipped()
                    .focusSection()
                    .accessibilityIdentifier("ntv.settings.details")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .foregroundStyle(NTVDesign.textPrimary)
        .padding(.horizontal, OrivioSpacing.huge)
        .padding(.top, OrivioSpacing.lg)
        .padding(.bottom, OrivioSpacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .fullScreenCover(isPresented: $editingProfile) {
            ProfileEditView(profile: profiles.active) { editingProfile = false }
                .environmentObject(theme)
                .environmentObject(profiles)
                .environmentObject(addonManager)
                .environmentObject(collections)
        }
        .onChange(of: theme.experienceMode) { _, _ in
            if !categories.contains(selected) { selected = .appearance }
        }
    }
}

private struct NTVSettingsCategoryLabel: View {
    @Environment(\.isFocused) private var focused
    let category: SettingsCategory
    let selected: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: category.icon).frame(width: 24)
            Text(category.railTitle).lineLimit(1).minimumScaleFactor(0.85)
            Spacer(minLength: 0)
        }
        .font(.system(size: 22, weight: .medium))
        .padding(.horizontal, 18)
        .frame(height: 58)
        .foregroundStyle(focused ? NTVDesign.background : NTVDesign.textPrimary)
        .background(focused ? NTVDesign.accent : selected ? NTVDesign.accentMuted : .clear,
                    in: RoundedRectangle(cornerRadius: 14))
    }
}
