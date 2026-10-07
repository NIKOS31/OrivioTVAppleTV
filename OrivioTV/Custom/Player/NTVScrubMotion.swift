import Foundation

/// Slow drags remain precise; fast swipes can traverse a long film. This only
/// moves the preview target: playback seeks once on confirmation, not per sample.
enum NTVScrubMotion {
    static func delta(points: Double, elapsed: Double, duration: Double) -> Double {
        guard points.isFinite, elapsed.isFinite, elapsed > 0, duration.isFinite, duration > 0 else { return 0 }
        let interval = min(max(elapsed, 1.0 / 120), 1)
        let speed = abs(points) / interval
        let gain = min(max((speed - 120) / 600, 0), 1)
        let secondsPerPoint = max(min(duration, 86_400) / 2400, 0.25)
        return min(max(points, -2048), 2048) * secondsPerPoint * (1 + 7 * gain * gain)
    }
}
