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

/// Coordinate the existing glass backgrounds without applying glass to the
/// focusable content itself or adding an effect to every poster.
struct NTVGlassGrouping: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(tvOS 26.0, *) {
            GlassEffectContainer(spacing: 12) { content }
        } else { content }
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
struct NTVPosterArtwork: View {
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
    let title: String
    let symbol: String
    let selected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 22, weight: .medium))
            Text(title).font(.system(size: 24, weight: .medium)).lineLimit(1)
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
    let tab: AppTab
    let selected: Bool
    let expanded: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: tab.icon)
                .font(.system(size: 26, weight: .medium))
                .frame(width: expanded ? 36 : 60)
            if expanded {
                Text(NTVBrand.navigationTitle(for: tab))
                    .font(.system(size: 24, weight: .medium))
                    .lineLimit(1)
                    .transition(.opacity)
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, expanded ? 14 : 0)
        .frame(height: 64)
        .frame(maxWidth: expanded ? .infinity : nil, alignment: .leading)
        .foregroundStyle(focused || selected ? NTVDesign.textPrimary : NTVDesign.textSecondary)
        .background {
            RoundedRectangle(cornerRadius: NTVDesign.controlRadius, style: .continuous)
                .fill(focused ? NTVDesign.textPrimary.opacity(0.22)
                      : selected ? NTVDesign.accentMuted : .clear)
        }
        .overlay {
            RoundedRectangle(cornerRadius: NTVDesign.controlRadius, style: .continuous)
                .strokeBorder(focused ? NTVDesign.accent : .clear, lineWidth: 2)
        }
        .accessibilityLabel(NTVBrand.navigationTitle(for: tab))
    }
}

struct NTVActionButtonStyle: ButtonStyle {
    var prominent = false
    var glass = false
    func makeBody(configuration: Configuration) -> some View {
        Chrome(configuration: configuration, prominent: prominent, glass: glass)
    }

    private struct Chrome: View {
        @Environment(\.isFocused) private var focused
        @Environment(\.legibilityWeight) private var legibility
        @ScaledMetric(relativeTo: .body) private var labelSize: CGFloat = 29
        let configuration: ButtonStyle.Configuration
        let prominent: Bool
        let glass: Bool

        var body: some View {
            configuration.label
                .font(.system(size: labelSize, weight: legibility == .bold ? .bold : .medium))
                .foregroundStyle(focused || prominent ? NTVDesign.background : NTVDesign.textPrimary)
                .padding(.horizontal, 28)
                .frame(minHeight: 70)
                .background {
                    if focused || prominent {
                        Capsule().fill(NTVDesign.textPrimary.opacity(focused ? 1 : 0.92))
                    } else if glass {
                        NTVGlassSurface(shape: Capsule(), clear: true)
                    } else {
                        Capsule().fill(.black.opacity(0.28))
                    }
                }
                .overlay {
                    Capsule().strokeBorder(.white.opacity(focused ? 0 : 0.16), lineWidth: 1)
                }
                .overlay {
                    Capsule().inset(by: -5).stroke(.white, lineWidth: 2)
                        .opacity(focused ? 1 : 0)
                }
                // Glass is opt-in for the few principal actions. Scrolling
                // rows keep the lighter alpha fill and the same focus cue.
                .focusLift(1.015, focused)
                .cardPressDip(configuration.isPressed)
        }
    }
}
