import SwiftUI

/// Background-only glass keeps custom controls in the tvOS focus engine.
/// Older hardware and Reduce Transparency use an opaque surface instead.
struct NTVGlassSurface<S: Shape>: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    let shape: S
    var emphasized = false
    var clear = false

    var body: some View {
        if reduceTransparency || contrast == .increased || PerformanceProfile.isLowPower || PerformanceProfile.isMidPower {
            shape.fill(emphasized ? NTVDesign.raised : NTVDesign.surface)
        } else if #available(tvOS 26.0, *) {
            if clear {
                Color.clear.glassEffect(.clear, in: shape)
            } else {
                Color.clear.glassEffect(
                    .regular.tint(NTVDesign.surface.opacity(emphasized ? 0.3 : 0.15)), in: shape)
            }
        } else {
            shape.fill(.regularMaterial)
        }
    }
}

/// The supplied nTV logo, preserving its original artwork and transparency.
struct NTVWordmark: View {
    var size: CGFloat = 36

    var body: some View {
        Image("NTVLogo")
            .renderingMode(.original)
            .resizable()
            .scaledToFit()
            .frame(width: size * 1.8, height: size * 1.5)
            .accessibilityLabel(NTVBrand.name)
            .accessibilityIdentifier("ntv.brand")
    }
}

/// Receives the real metadata artwork URL; never owns an addon or catalog.
struct NTVPosterArtwork: View, Equatable {
    let imageURL: String?
    let title: String
    let width: CGFloat
    let height: CGFloat
    let focused: Bool
    let watched: Bool
    let progress: Double?
    let shadowsEnabled: Bool
    var placeholderSymbol = "film"
    var cornerRadius: CGFloat = NTVDesign.cardRadius

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            if let imageURL, !imageURL.isEmpty {
                RemoteImage(url: imageURL, maxDimension: height)
                    .aspectRatio(2 / 3, contentMode: .fill)
            } else {
                VStack(spacing: 18) {
                    Image(systemName: placeholderSymbol)
                        .font(.system(size: 38, weight: .light))
                        .foregroundStyle(NTVDesign.textSecondary)
                    Text(title)
                        .font(.system(size: 23, weight: .medium))
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .foregroundStyle(NTVDesign.textPrimary)
                }
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if let progress, progress.isFinite, progress > 0 {
                ProgressStrip(fraction: progress)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
            }
        }
        .frame(width: width, height: height)
        .background(NTVDesign.raised)
        .clipShape(shape)
        .overlay(alignment: .topTrailing) {
            if watched { WatchedBadge().padding(12) }
        }
        // Always visible, including when parallax, zoom or motion is disabled.
        .overlay(shape.strokeBorder(focused ? NTVDesign.accent : .clear, lineWidth: 3))
        .shadow(color: .black.opacity(focused && shadowsEnabled ? 0.5 : 0), radius: 18, y: 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
    }
}

struct NTVNavigationLabel: View {
    @Environment(\.isFocused) private var focused
    let tab: AppTab
    let selected: Bool

    var body: some View {
        HStack(spacing: 10) {
            tab.navigationIcon.font(.system(size: 22, weight: .medium))
            Text(NTVBrand.navigationTitle(for: tab)).font(.system(size: 24, weight: .medium)).lineLimit(1)
        }
        .foregroundStyle(focused || selected ? NTVDesign.textPrimary : NTVDesign.textSecondary)
        .padding(.horizontal, 20)
        .frame(height: 60)
        .background {
            RoundedRectangle(cornerRadius: NTVDesign.controlRadius, style: .continuous)
                .fill(focused || selected ? NTVDesign.accentMuted : .clear)
        }
        .overlay {
            RoundedRectangle(cornerRadius: NTVDesign.controlRadius, style: .continuous)
                .strokeBorder(focused ? NTVDesign.accent : .clear, lineWidth: 2)
        }
    }
}

/// A compact rail expands its labels only while the remote is in the menu.
struct NTVSidebarLabel: View {
    @Environment(\.isFocused) private var focused
    @ScaledMetric(relativeTo: .body) private var labelSize: CGFloat = 29
    let tab: AppTab
    let selected: Bool
    let expanded: Bool

    var body: some View {
        HStack(spacing: 4) {
            // One icon column, open or closed: the icon never shifts (build 59).
            tab.navigationIcon
                .font(.system(size: 25, weight: .medium))
                .frame(width: 56)
            // A zero-width hidden label still enlarges the native button's focus frame.
            if expanded {
                Text(NTVBrand.navigationTitle(for: tab))
                    .font(.system(size: labelSize, weight: focused || selected ? .bold : .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .transition(.opacity.combined(with: .offset(x: -10)))
                Spacer(minLength: 0)
            }
        }
        .padding(.trailing, expanded ? 14 : 0)
        .frame(minHeight: 56)
        .frame(maxWidth: expanded ? .infinity : nil, alignment: .leading)
        .foregroundStyle(focused || selected ? NTVDesign.textPrimary : NTVDesign.textSecondary)
        .background {
            RoundedRectangle(cornerRadius: NTVDesign.controlRadius, style: .continuous)
                .fill(focused ? Color.white.opacity(0.34)
                      : selected ? Color.white.opacity(0.08) : .clear)
        }
        // The open section stays marked at a glance, rail open or closed.
        .overlay(alignment: .leading) {
            Capsule(style: .continuous)
                .fill(NTVDesign.textPrimary)
                .frame(width: 4, height: 24)
                .offset(x: -9)
                .opacity(selected && !focused ? 1 : 0)
                .accessibilityHidden(true)
        }
        .accessibilityLabel(NTVBrand.navigationTitle(for: tab))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .animation(PerformanceSettingsStore.shared.sidebarAnimationEffective
                   ? (expanded ? FusionMotion.focusEntry : FusionMotion.focusExit) : nil, value: expanded)
    }
}

struct NTVActionButtonStyle: ButtonStyle {
    var prominent = false
    var glass = false
    var capsule = false
    func makeBody(configuration: Configuration) -> some View {
        Chrome(configuration: configuration, prominent: prominent, glass: glass, capsule: capsule)
    }

    private struct Chrome: View {
        @Environment(\.isFocused) private var focused
        @Environment(\.legibilityWeight) private var legibility
        @ScaledMetric(relativeTo: .body) private var labelSize: CGFloat = 29
        let configuration: ButtonStyle.Configuration
        let prominent: Bool
        let glass: Bool
        let capsule: Bool
        private var radius: CGFloat { capsule ? 100 : NTVDesign.controlRadius }

        // Build 59: one button language. At rest a translucent pill that lets
        // the artwork through (the principal action a little brighter); in
        // focus solid off-white with dark text, lifted with a soft neutral
        // shadow. The second white ring around the focused button is gone:
        // the fill change already reads from the sofa.
        var body: some View {
            let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
            configuration.label
                .font(.system(size: capsule ? labelSize * 0.86 : labelSize, weight: legibility == .bold ? .bold : .medium))
                .foregroundStyle(focused ? NTVDesign.background : NTVDesign.textPrimary)
                .padding(.horizontal, capsule ? 20 : 28)
                .frame(minHeight: capsule ? 56 : 70)
                .background {
                    if focused {
                        shape.fill(NTVDesign.textPrimary)
                    } else if glass {
                        NTVGlassSurface(shape: shape, clear: true)
                    } else {
                        shape.fill(Color.white.opacity(prominent ? 0.22 : 0.12))
                    }
                }
                .overlay {
                    shape.strokeBorder(.white.opacity(focused ? 0 : 0.08), lineWidth: 1)
                }
                .shadow(color: .black.opacity(focused ? 0.45 : 0), radius: 16, y: 8)
                .focusLift(1.05, focused)
                .cardPressDip(configuration.isPressed)
        }
    }
}
