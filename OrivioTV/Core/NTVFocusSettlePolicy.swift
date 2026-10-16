import Foundation

/// Coalesce hero work during a fast touch sweep. Keep the ordinary response
/// for isolated steps; rapid steps should not start decoding a full-screen
/// image for every intermediate poster. Uses monotonic uptime, not wall time.
struct NTVFocusSettlePolicy {
    private var previous: Double?

    mutating func delay(at uptime: Double, minimumNanoseconds: UInt64) -> UInt64 {
        guard uptime.isFinite else { return minimumNanoseconds }
        defer { previous = uptime }
        guard let previous, uptime >= previous, uptime - previous < 0.14 else { return minimumNanoseconds }
        return max(minimumNanoseconds, 180_000_000)
    }
}
