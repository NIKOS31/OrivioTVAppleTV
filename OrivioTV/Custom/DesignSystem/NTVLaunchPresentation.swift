import SwiftUI

/// One presentation per app process, including when a scene is reconstructed.
@MainActor final class NTVLaunchSession {
    static let shared = NTVLaunchSession()
    private var presented = false
    func claim() -> Bool {
        guard !presented else { return false }
        presented = true
        return true
    }
}

/// Animates the bundled mark and one small gradient. No video or shader.
@MainActor struct NTVLaunchPresentation: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var visible = false
    @State private var entered = false
    @State private var departing = false

    func body(content: Content) -> some View {
        content.overlay {
            if visible {
                ZStack {
                    NTVDesign.background.ignoresSafeArea()
                    RadialGradient(colors: [Color.blue.opacity(0.24), Color.cyan.opacity(0.05), .clear],
                        center: .center, startRadius: 12, endRadius: 150)
                        .frame(width: 300, height: 300)
                        .scaleEffect(entered ? 1 : 0.7)
                        .opacity(entered ? 1 : 0)
                    NTVWordmark(size: 156)
                        .scaleEffect(reduceMotion ? 1 : departing ? 1.07 : entered ? 1 : 0.74)
                        .rotation3DEffect(.degrees(reduceMotion || entered ? 0 : -12),
                                          axis: (x: 0, y: 1, z: 0))
                        .offset(y: reduceMotion || entered ? 0 : 16)
                        .opacity(entered ? 1 : 0)
                }
                .opacity(departing ? 0 : 1)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
        .task(id: scenePhase) {
            // Cancellation when the app leaves the foreground hides the logo.
            // Its process-wide claim is consumed, so returning never replays it.
            guard scenePhase == .active else { visible = false; return }
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains(where: { $0.contains("Demo") || $0.contains("Probe") }) {
                return
            }
            #endif
            guard NTVLaunchSession.shared.claim() else { return }
            visible = true
            await Task.yield()
            guard !Task.isCancelled else { visible = false; return }
            withAnimation(reduceMotion ? nil : .spring(response: 0.72, dampingFraction: 0.76)) {
                entered = true
            }
            do {
                try await Task.sleep(nanoseconds: reduceMotion ? 1_600_000_000 : 1_900_000_000)
                if reduceMotion { visible = false; return }
                withAnimation(.easeInOut(duration: 0.4)) { departing = true }
                try await Task.sleep(nanoseconds: 400_000_000)
                visible = false
            } catch { visible = false }
        }
    }
}
