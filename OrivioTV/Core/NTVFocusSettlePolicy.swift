import Foundation

/// Coalesce hero work during a fast touch sweep. Keep the ordinary response
/// for isolated steps; rapid steps should not start decoding a full-screen
/// image for every intermediate poster. Uses monotonic uptime, not wall time.
struct NTVFocusSettlePolicy {
    private var previous: Double?

    mutating func delay(at uptime: Double, minimumNanoseconds: UInt64) -> UInt64 {
        guard uptime.isFinite else { return minimumNanoseconds }
        defer { previous = uptime }
        // D-pad repeats and row landings commonly arrive 150–280ms apart.
        // The old 140ms cutoff treated each as an isolated step, starting
        // metadata, poster fades and text layout during every focus animation.
        guard let previous, uptime >= previous, uptime - previous < 0.35 else { return minimumNanoseconds }
        return max(minimumNanoseconds, 300_000_000)
    }
}
