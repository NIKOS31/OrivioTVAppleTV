import SwiftUI

/// Public identity only. Protocol names, account endpoints and persistence
/// identifiers remain owned by the upstream engine.
enum NTVBrand {
    static let name = "nTV"

    static func navigationTitle(for tab: AppTab) -> String {
        switch tab {
        case .home: return "Accueil"
        case .movies: return "Films"
        case .series: return "Séries"
        case .addons: return "Addons"
        case .search: return "Recherche"
        case .library: return "Bibliothèque"
        case .settings: return "Réglages"
        case .liveTV: return "TV en direct"
        }
    }
}

enum NTVDesign {
    static let background = Color(hex: 0x101218)
    static let surface = Color(hex: 0x1A1F27)
    static let raised = Color(hex: 0x252D37)
    // Keep the supplied blue logo distinct from neutral application controls.
    static let accent = Color(hex: 0xD7E2E7)
    static let accentMuted = Color(hex: 0x303D49)
    static let textPrimary = Color(hex: 0xF3F4F6)
    static let textSecondary = Color(hex: 0xADB7C2)
    static let cardRadius: CGFloat = 18
    static let controlRadius: CGFloat = 14
    static let controlFocusScale: CGFloat = 1.025
    static let sidebarExpandedWidth: CGFloat = 280

    static let palette = ThemePalette(
        id: "ntv-night", displayName: "nTV — Nuit",
        secondary: accent,
        secondaryVariant: Color(hex: 0xA8B7C1),
        onSecondary: background,
        focusRing: accent,
        focusBackground: accentMuted,
        background: background,
        backgroundElevated: surface,
        backgroundCard: raised,
        surface: surface,
        surfaceVariant: raised,
        panel: surface,
        overlay: background.opacity(0.92),
        field: raised,
        textPrimary: textPrimary,
        textSecondary: textSecondary,
        textTertiary: textSecondary
    )
}
