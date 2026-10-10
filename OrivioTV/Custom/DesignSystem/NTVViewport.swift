import SwiftUI

enum NTVViewport {
    static let horizontalInset: CGFloat = 48
    static let posterGap: CGFloat = 24

    static func posterWidth(available: CGFloat, preferred: CGFloat) -> CGFloat {
        guard available.isFinite, preferred.isFinite, available > 0, preferred > 0 else { return 210 }
        let count = max(1, Int((available + posterGap) / (preferred + posterGap)))
        return max(1, (available - CGFloat(count - 1) * posterGap) / CGFloat(count))
    }
}

struct NTVFullWidthViewport: ViewModifier {
    let enabled: Bool
    @ViewBuilder func body(content: Content) -> some View {
        if enabled { content.ignoresSafeArea(edges: .horizontal) }
        else { content }
    }
}

/// The root owns this object without observing its artwork. Only the canvas
/// redraws when focus changes, preserving the catalog rows' rendering policy.
@MainActor final class NTVBackdropCanvas: ObservableObject {
    @Published private(set) var url: String?
    private var active: String?
    private var images: [String: String] = [:]

    func activate(_ identifier: String?) {
        active = identifier
        url = identifier.flatMap { images[$0] }
    }
    func update(_ identifier: String, url: String?) {
        images[identifier] = url
        if active == identifier { self.url = url }
    }
    func clear() { images = [:]; url = nil }
}

struct NTVCanvasBackdrop: View {
    @ObservedObject var canvas: NTVBackdropCanvas
    @ObservedObject private var performance = PerformanceSettingsStore.shared
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                NTVDesign.background
                if performance.settings.heroBackdrop, let url = canvas.url {
                    RemoteImage(url: url, maxDimension: geometry.size.width,
                                maxPixels: PerformanceProfile.backdropPixelCap)
                        .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                    LinearGradient(colors: [NTVDesign.background.opacity(0.82), NTVDesign.background.opacity(0.25)],
                                   startPoint: .leading, endPoint: .trailing)
                    LinearGradient(colors: [.clear, NTVDesign.background.opacity(0.94)],
                                   startPoint: .top, endPoint: .bottom)
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Fond plein écran")
        .accessibilityIdentifier("ntv.canvas")
    }
}
