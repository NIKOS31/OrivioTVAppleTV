import SwiftUI

/// Temporary wordmark until the supplied logo is available.
struct NTVWordmark: View {
    var size: CGFloat = 36

    var body: some View {
        Text(NTVBrand.name)
            .font(.system(size: size, weight: .semibold))
            .kerning(-1)
            .foregroundStyle(NTVDesign.textPrimary)
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
                .foregroundStyle(focused ? NTVDesign.background : NTVDesign.textPrimary)
                .padding(.horizontal, 26)
                .frame(minHeight: 60)
                .background {
                    RoundedRectangle(cornerRadius: NTVDesign.controlRadius, style: .continuous)
                        .fill(focused ? NTVDesign.accent : NTVDesign.raised)
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
