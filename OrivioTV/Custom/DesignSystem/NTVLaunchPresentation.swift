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
    @State private var settled = false
    @State private var departing = false

    init() {
        var enabled = true
        #if DEBUG
        enabled = !ProcessInfo.processInfo.arguments.contains(where: {
            $0.contains("Demo") || $0.contains("Probe")
        })
        #endif
        _visible = State(initialValue: enabled && NTVLaunchSession.shared.claim())
    }

    func body(content: Content) -> some View {
        // Mount the root after the introduction. Its onboarding/profile covers
        // otherwise present over a root overlay and hide the mark on first use.
        Group {
            if visible {
                ZStack {
                    NTVDesign.background.ignoresSafeArea()
                    RadialGradient(colors: [Color.blue.opacity(0.24), Color.cyan.opacity(0.05), .clear],
                        center: .center, startRadius: 12, endRadius: 150)
                        .frame(width: 300, height: 300)
                        .scaleEffect(settled ? 1.12 : entered ? 1 : 0.7)
                        .opacity(entered ? 1 : 0)
                    NTVWordmark(size: 156)
                        .scaleEffect(reduceMotion ? 1 : departing ? 1.12 : settled ? 1.025 : entered ? 1 : 0.74)
                        .rotation3DEffect(.degrees(reduceMotion || entered ? 0 : -12),
                                          axis: (x: 0, y: 1, z: 0))
                        .offset(y: reduceMotion || entered ? 0 : 16)
                        .opacity(entered ? 1 : 0)
                        .accessibilityIdentifier("ntv.launch.logo")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .ignoresSafeArea()
                .opacity(departing ? 0 : 1)
                .allowsHitTesting(false)
            } else {
                content
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // Ignore the transient inactive phase during scene creation.
            // Going home consumes this launch; activation cannot replay it.
            if phase == .background { visible = false }
        }
        .task {
            guard visible else { return }
            do {
                // Give the initial pose a rendered frame before animating it.
                try await Task.sleep(nanoseconds: 80_000_000)
                guard visible else { return }
                withAnimation(reduceMotion ? nil : .spring(response: 0.8, dampingFraction: 0.78)) {
                    entered = true
                }
                try await Task.sleep(nanoseconds: reduceMotion ? 1_600_000_000 : 800_000_000)
                if reduceMotion { visible = false; return }
                guard visible else { return }
                withAnimation(.easeInOut(duration: 1.1)) { settled = true }
                var hold: UInt64 = 1_550_000_000
                #if DEBUG
                // XCTest needs time to inspect the settled pose. The exported
                // launch movie uses no flag and records the normal 3s timing.
                if ProcessInfo.processInfo.arguments.contains("-ntvLaunchTest") { hold = 20_000_000_000 }
                #endif
                try await Task.sleep(nanoseconds: hold)
                guard visible else { return }
                withAnimation(.easeInOut(duration: 0.6)) { departing = true }
                try await Task.sleep(nanoseconds: 600_000_000)
                visible = false
            } catch { visible = false }
        }
    }
}
