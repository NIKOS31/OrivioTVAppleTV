import Foundation

/// Nuvio PlayerSurfaceGestures.kt (GPL-3.0): a fixed anchor and a linear
/// 60/90/120-second range per viewport; the gesture commits on release.
enum NTVScrubMotion {
    static func position(points: Double, viewportWidth: Double, anchor: Double, duration: Double) -> Double {
        guard points.isFinite, viewportWidth.isFinite, viewportWidth > 0,
              anchor.isFinite, duration.isFinite, duration > 0 else { return 0 }
        let range: Double = duration >= 3600 ? 120 : duration >= 1800 ? 90 : 60
        // A remote can project beyond the window; cap one contact to one viewport.
        let fraction = min(max(points / viewportWidth, -1), 1)
        let end = max(duration - 1, 0)
        return max(0, min(min(max(anchor, 0), end) + fraction * range, end))
    }
}
