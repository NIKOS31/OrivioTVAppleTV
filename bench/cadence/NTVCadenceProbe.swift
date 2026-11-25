import SwiftUI
import QuartzCore

/// Benchmark-only (perf/ntv-cadence-*): records FrameCadenceWindow snapshots
/// and exposes them through accessibility only when XCTest reads the value,
/// so the probe publishes nothing per frame. Callback cadence on the main run
/// loop, not GPU presentation. Content-free: no IDs, titles, URLs or profiles.
enum NTVCadenceProbe {
    static let isRequested: Bool = {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-ntvCadenceProbe")
        #else
        false
        #endif
    }()
}

/// Benchmark-only counters for code that NTVRenderScope does not cover (the
/// 57 UIKit container). Bounded: one entry per fixed key, no per-event log.
@MainActor enum NTVBenchCounters {
    private(set) static var values: [String: (count: Int, milliseconds: Double)] = [:]
    static func count(_ key: String, milliseconds: Double = 0) {
        let old = values[key] ?? (0, 0)
        values[key] = (old.count + 1, old.milliseconds + milliseconds)
    }
    static func measure<T>(_ key: String, _ work: () -> T) -> T {
        let start = CACurrentMediaTime()
        defer { count(key, milliseconds: (CACurrentMediaTime() - start) * 1000) }
        return work()
    }
}

struct NTVCadenceProbeView: UIViewRepresentable {
    func makeUIView(context: Context) -> NTVCadenceProbeUIView { NTVCadenceProbeUIView() }
    func updateUIView(_ view: NTVCadenceProbeUIView, context: Context) {}
}

@MainActor private final class NTVCadenceProbeTarget: NSObject {
    weak var view: NTVCadenceProbeUIView?
    init(_ view: NTVCadenceProbeUIView) { self.view = view; super.init() }
    @objc func tick(_ link: CADisplayLink) { view?.tick(link) }
}

final class NTVCadenceProbeUIView: UIView {
    private var link: CADisplayLink?
    private var cadence = FrameCadenceWindow()
    // "end,duration,callbacks,worstMs,late" per ~1 s window; capped, oldest dropped.
    private var records: [String] = []
    private var dropped = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = false
        isAccessibilityElement = true
        accessibilityIdentifier = "ntv.bench.cadence"
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        link?.invalidate(); link = nil
        guard window != nil else { return }
        cadence = FrameCadenceWindow()
        let l = CADisplayLink(target: NTVCadenceProbeTarget(self), selector: #selector(NTVCadenceProbeTarget.tick(_:)))
        l.add(to: .main, forMode: .common)
        link = l
    }

    fileprivate func tick(_ link: CADisplayLink) {
        let maxRefresh = max(UIScreen.main.maximumFramesPerSecond, 1)
        let expected = max(link.targetTimestamp - link.timestamp, 1 / Double(maxRefresh))
        guard let s = cadence.record(timestamp: link.timestamp, expectedInterval: expected) else { return }
        let callbacks = Int((Double(s.callbacksPerSecond) * s.sampleDuration).rounded())
        records.append(String(format: "%.4f,%.4f,%d,%.2f,%d", link.timestamp, s.sampleDuration,
                              callbacks, s.worstGapMilliseconds, s.lateCallbacks))
        if records.count > 900 { records.removeFirst(); dropped += 1 }
    }

    override var accessibilityValue: String? {
        get {
            let counters = NTVRenderProbe.snapshot() ?? [:]
            let work = NTVRenderScope.allCases.map { scope -> String in
                let sample = counters[scope] ?? .init()
                return String(format: "%@=%d/%.3f", scope.rawValue, sample.evaluations, sample.totalMilliseconds)
            }.joined(separator: ",")
            let bench = NTVBenchCounters.values.keys.sorted().map { key -> String in
                let value = NTVBenchCounters.values[key]!
                return String(format: "%@=%d/%.3f", key, value.count, value.milliseconds)
            }.joined(separator: ",")
            return String(format: "now=%.4f|dropped=%d|", CACurrentMediaTime(), dropped)
                + records.joined(separator: ";") + "|" + work + "|" + bench
        }
        set {}
    }

    deinit { link?.invalidate() }
}
