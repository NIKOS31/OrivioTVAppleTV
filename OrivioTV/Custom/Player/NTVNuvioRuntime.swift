// SPDX-License-Identifier: GPL-3.0-only
// Swift port of NuvioDesktop PlayerLayout.kt formatPlaybackTime/Runtime,
// revision d2e21f20782f4516b62bbdcb4764d6271db1d614 (0.1.30-alpha).
// Original project: https://github.com/NuvioMedia/NuvioDesktop
import Foundation

enum NTVNuvioRuntime {
    /// The tvOS clock is in seconds; Nuvio's clock is in milliseconds.
    /// Floor the value, matching integer millisecond division in Kotlin.
    static func time(_ seconds: Double) -> String {
        let total = Int(safe(seconds).rounded(.down))
        let sec = String(total % 60).paddingLeft(to: 2)
        let min = String((total / 60) % 60).paddingLeft(to: 2)
        return total >= 3600 ? "\(total / 3600):\(min):\(sec)" : "\(min):\(sec)"
    }

    static func text(position: Double, duration: Double, remaining: Bool) -> String {
        if remaining { return "−" + time(max(safe(duration) - safe(position), 0)) }
        return time(position) + " / " + time(duration)
    }

    private static func safe(_ seconds: Double) -> Double {
        guard seconds.isFinite else { return 0 }
        // Guard conversion from a malformed engine duration. This bound is
        // over 68 years, well beyond a playable item, and fits all targets.
        return min(max(seconds, 0), Double(Int32.max))
    }
}

private extension String {
    func paddingLeft(to length: Int) -> String {
        String(repeating: "0", count: Swift.max(length - count, 0)) + self
    }
}
