import SwiftUI

/// Public identity only. Protocol names, account endpoints and persistence
/// identifiers remain owned by the upstream engine.
enum NTVBrand {
    static let name = "nTV"

    static func navigationTitle(for tab: AppTab) -> String {
        switch tab {
        case .home: return "Accueil"
        case .search: return "Recherche"
        case .library: return "Bibliothèque"
        case .settings: return "Réglages"
        case .liveTV: return "TV en direct"
        }
    }
}

enum NTVDesign {
    static let background = Color(hex: 0x080E1B)
    static let surface = Color(hex: 0x111B2D)
    static let raised = Color(hex: 0x19263B)
    static let accent = Color(hex: 0x6F9FFF)
    static let accentMuted = Color(hex: 0x223655)
    static let textPrimary = Color(hex: 0xF1F4FA)
    static let textSecondary = Color(hex: 0xA4B1C6)
    static let cardRadius: CGFloat = 18
    static let controlRadius: CGFloat = 14
    static let controlFocusScale: CGFloat = 1.025

    static let palette = ThemePalette(
        id: "ntv-night", displayName: "nTV — Bleu nuit",
        secondary: accent,
        secondaryVariant: Color(hex: 0x3A69BD),
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
