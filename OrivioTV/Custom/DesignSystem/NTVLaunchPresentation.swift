import SwiftUI

/// One short opacity transition over the bundled logo; no video, shader or blur.
struct NTVLaunchPresentation: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible = true

    func body(content: Content) -> some View {
        content.overlay {
            if visible {
                NTVDesign.background.ignoresSafeArea()
                    .overlay { NTVWordmark(size: 76) }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    .transition(.opacity)
            }
        }
        .task {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains(where: { $0.contains("Demo") || $0.contains("Probe") }) {
                visible = false
                return
            }
            #endif
            try? await Task.sleep(nanoseconds: reduceMotion ? 200_000_000 : 500_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) { visible = false }
        }
    }
}
