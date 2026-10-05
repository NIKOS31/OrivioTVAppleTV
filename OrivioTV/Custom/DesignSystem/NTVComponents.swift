import SwiftUI

/// Background-only glass keeps custom controls in the tvOS focus engine.
/// Older hardware and Reduce Transparency use an opaque surface instead.
struct NTVGlassSurface<S: Shape>: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let shape: S
    var emphasized = false
    var clear = false

    var body: some View {
        if reduceTransparency || PerformanceProfile.isLowPower || PerformanceProfile.isMidPower {
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
    func makeBody(configuration: Configuration) -> some View {
        Chrome(configuration: configuration)
    }

    private struct Chrome: View {
        @Environment(\.isFocused) private var focused
        let configuration: ButtonStyle.Configuration

        var body: some View {
            configuration.label
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(NTVDesign.textPrimary)
                .padding(.horizontal, 26)
                .frame(minHeight: 60)
                .background {
                    if focused {
                        NTVGlassSurface(shape: RoundedRectangle(
                            cornerRadius: NTVDesign.controlRadius, style: .continuous), emphasized: true)
                    } else {
                        RoundedRectangle(cornerRadius: NTVDesign.controlRadius, style: .continuous)
                            .fill(NTVDesign.raised)
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: NTVDesign.controlRadius, style: .continuous)
                        .strokeBorder(focused ? NTVDesign.accent : .clear, lineWidth: 2)
                }
                .focusLift(NTVDesign.controlFocusScale, focused)
                .cardPressDip(configuration.isPressed)
        }
    }
}
