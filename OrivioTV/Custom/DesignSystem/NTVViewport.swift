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

/// Reserve menu clearance on root pages, never on the NavigationStack itself.
/// A pushed detail gets the same full-screen viewport from its first frame;
/// removing the menu must not resize its image during the push transition.
struct NTVPageTopClearance: ViewModifier {
    var isHome = false
    @ScaledMetric(relativeTo: .body) private var topClearance: CGFloat = NTVDesign.topChromeClearance
    @EnvironmentObject private var theme: ThemeManager
    @Environment(\.navigationIsTop) private var navigationIsTop
    func body(content: Content) -> some View {
        content.padding(.top, navigationIsTop && theme.palette.id == NTVDesign.palette.id
                         ? topClearance : 0)
            .padding(.leading, !navigationIsTop && !isHome && theme.palette.id == NTVDesign.palette.id
                     ? NTVDesign.sidebarClearance : 0)
    }
}

/// The root owns this object without observing its artwork. Only the canvas
/// redraws when focus changes, preserving the catalog rows' rendering policy.
private struct NTVBackdropCanvasKey: EnvironmentKey {
    static let defaultValue: NTVBackdropCanvas? = nil
}
extension EnvironmentValues {
    /// Reporting layers need a reference, not a subscription to artwork.
    var ntvBackdropCanvas: NTVBackdropCanvas? {
        get { self[NTVBackdropCanvasKey.self] }
        set { self[NTVBackdropCanvasKey.self] = newValue }
    }
}

@MainActor final class NTVBackdropCanvas: ObservableObject {
    @Published private(set) var url: String?
    private var active: String?
    private var images: [String: String] = [:]
    private var pending: Task<Void, Never>?
    private let settleDelay: Duration

    init(settleDelay: Duration = .milliseconds(180)) { self.settleDelay = settleDelay }

    func activate(_ identifier: String?) {
        guard active != identifier else { return }
        pending?.cancel()
        active = identifier
        let next = identifier.flatMap { images[$0] }
        if url != next { url = next }
    }
    func update(_ identifier: String, url: String?) {
        images[identifier] = url
        guard active == identifier else { return }
        // Cancel before equality: X → Y → X must cancel the pending Y.
        pending?.cancel()
        guard self.url != url else { return }
        // First artwork and explicitly cleared artwork do not wait.
        guard self.url != nil, url != nil else { self.url = url; return }
        pending = Task { @MainActor [weak self, settleDelay] in
            do { try await Task.sleep(for: settleDelay) } catch { return }
            guard let self, !Task.isCancelled, self.active == identifier,
                  self.images[identifier] == url, self.url != url else { return }
            self.url = url
        }
    }
    func clear() { pending?.cancel(); images = [:]; url = nil }
}

struct NTVCanvasBackdrop: View {
    @ObservedObject var canvas: NTVBackdropCanvas
    @ObservedObject private var performance = PerformanceSettingsStore.shared
    var body: some View {
        let _ = NTVRenderProbe.evaluated(.canvas)
        GeometryReader { geometry in
            ZStack {
                NTVDesign.background
                if performance.settings.heroBackdrop, let url = canvas.url {
                    RemoteImage(url: url, maxDimension: geometry.size.width,
                                maxPixels: PerformanceProfile.backdropPixelCap)
                        .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                    LinearGradient(colors: [NTVDesign.background.opacity(0.94), NTVDesign.background.opacity(0.52)],
                                   startPoint: .leading, endPoint: .trailing)
                    LinearGradient(colors: [NTVDesign.background.opacity(0.12), NTVDesign.background.opacity(0.98)],
                                   startPoint: .top, endPoint: .bottom)
                }
            }
        }
        .ignoresSafeArea()
        .ntvHalloweenDecor(.stage)
        // The edge ornament uses the screen edge, not the inset content area.
        // It cannot drift onto a shelf's See All control as that shelf scrolls.
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Fond plein écran")
        .accessibilityIdentifier("ntv.canvas")
    }
}
