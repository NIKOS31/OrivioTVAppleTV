import Foundation

/// Slow drags remain precise; faster swipes move a little farther. This only
/// moves the preview target: playback seeks once on confirmation, not per sample.
enum NTVScrubMotion {
    static func delta(points: Double, elapsed: Double, duration: Double) -> Double {
        guard points.isFinite, elapsed.isFinite, elapsed > 0, duration.isFinite, duration > 0 else { return 0 }
        let interval = min(max(elapsed, 1.0 / 120), 1)
        let speed = abs(points) / interval
        let gain = min(max((speed - 120) / 600, 0), 1)
        let proposed = min(max(points, -2048), 2048) * 0.03 * (1 + 2 * gain * gain)
        // UIKit can project a small remote gesture into many window points.
        // A single sample must never jump across a large part of the film.
        return min(max(proposed, -5), 5)
    }

    static func position(proposed: Double, anchor: Double, duration: Double) -> Double {
        guard proposed.isFinite, anchor.isFinite, duration.isFinite, duration > 0 else { return 0 }
        let budget = min(90, duration * 0.1)
        return max(0, min(duration - 1, min(max(proposed, anchor - budget), anchor + budget)))
    }
}
