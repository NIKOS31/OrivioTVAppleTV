import SwiftUI
import QuartzCore

/// Developer diagnostic: a live frames-per-second read-out, driven by a
/// CADisplayLink callback cadence on the main run loop, not a measurement of
/// GPU/compositor presentation. Toggled by Settings → Performance → Show FPS
/// overlay; attached once at the app root so it measures the whole UI.
///
/// Colour-coded against the display's own max refresh (usually 60): green =
/// smooth, amber = some drops, red = janky — so the effect switches can be
/// tuned by eye on the real Apple TV.
struct FPSOverlay: View {
    @StateObject private var meter = FrameMeter()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Circle()
                    .fill(color)
                    .frame(width: 12, height: 12)
                Text("UI \(meter.fps) Hz · max \(Int(meter.snapshot.worstGapMilliseconds.rounded())) ms · \(meter.snapshot.lateCallbacks) retards")
                    .font(.system(size: 22, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
            }
            if let diagnostic = meter.navigationSample {
                Text(diagnostic.summary)
                    .font(.system(size: 18, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 24).fill(Color.black.opacity(meter.navigationSample == nil ? 0.72 : 0.82)))
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(color.opacity(0.8), lineWidth: 2))
        .padding(.top, 112)
        .padding(.trailing, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .allowsHitTesting(false)   // never eats focus/clicks
        .onAppear { meter.start() }
        .onDisappear { meter.stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { meter.start() } else { meter.stop() }
        }
    }

    private var color: Color {
        let target = Double(meter.snapshot.targetRate > 0 ? meter.snapshot.targetRate : max(meter.maxRefresh, 1))
        switch Double(meter.fps) / target {
        case 0.9...:   return .green
        case 0.6..<0.9: return .yellow
        default:       return .red
        }
    }
}

struct FrameCadenceSnapshot: Equatable {
    var callbacksPerSecond = 0
    var targetRate = 0
    var worstGapMilliseconds: Double = 0
    var lateCallbacks = 0
    var sampleDuration: Double = 0
}

/// A callback arriving late indicates main-run-loop delay. It cannot tell
/// whether the GPU presented an image, or attribute a delay to a specific view.
struct FrameCadenceWindow {
    private var start: Double?
    private var previous: Double?
    private var callbacks = 0
    private var worstGap: Double = 0
    private var late = 0

    mutating func record(timestamp: Double, expectedInterval: Double) -> FrameCadenceSnapshot? {
        guard timestamp.isFinite, expectedInterval.isFinite, expectedInterval > 0 else { return nil }
        guard let start, let previous else {
            self.start = timestamp; self.previous = timestamp; return nil
        }
        guard timestamp >= previous else { self = FrameCadenceWindow(); return nil }
        let gap = timestamp - previous
        self.previous = timestamp
        callbacks += 1
        worstGap = max(worstGap, gap)
        if gap > expectedInterval * 1.5 { late += 1 }
        let elapsed = timestamp - start
        guard elapsed >= 1 else { return nil }
        let result = FrameCadenceSnapshot(callbacksPerSecond: Int((Double(callbacks) / elapsed).rounded()),
                                         targetRate: Int(min(max(1 / expectedInterval, 1), 240).rounded()),
                                         worstGapMilliseconds: worstGap * 1000,
                                         lateCallbacks: late, sampleDuration: elapsed)
        self.start = timestamp; callbacks = 0; worstGap = 0; late = 0
        return result
    }
}

/// Counts from the SAME callback window, not lifetime counts or GPU timings.
struct NTVNavigationSample: Equatable {
    let cadence: FrameCadenceSnapshot
    let evaluations: [NTVRenderScope: Int]
    let filteringMilliseconds: Double

    var summary: String {
        func count(_ scope: NTVRenderScope) -> Int { evaluations[scope, default: 0] }
        return "Pic local, gardé 15 s : \(cadence.callbacksPerSecond) Hz / \(Int(cadence.worstGapMilliseconds.rounded())) ms\n"
            + "Fenêtre \(String(format: "%.1f", cadence.sampleDuration)) s · sections \(count(.settingsSelection)) · Haut/Bas \(count(.catalogVerticalMove))\n"
            + "Évals : racine \(count(.root)) · réglages \(count(.settings))/\(count(.settingsPane))/\(count(.settingsGroup))\n"
            + "Catalogue \(count(.catalog)) · rangées \(count(.posterRow)) · cartes \(count(.posterCell))\n"
            + "Filtres : \(String(format: "%.2f", filteringMilliseconds)) ms · Évals ≠ images GPU"
    }
}

/// Holds one worst window for reading after releasing the remote; no event log.
struct NTVNavigationWindow {
    private var previous: [NTVRenderScope: NTVRenderMeter.Sample]?
    private var held: NTVNavigationSample?
    private var heldAt = 0.0

    init(baseline: [NTVRenderScope: NTVRenderMeter.Sample]? = nil) { previous = baseline }

    mutating func record(cadence: FrameCadenceSnapshot,
                         counters: [NTVRenderScope: NTVRenderMeter.Sample]?,
                         now: Double) -> NTVNavigationSample? {
        guard let counters, now.isFinite else { self = NTVNavigationWindow(); return nil }
        defer { previous = counters }
        guard let previous else { return nil }
        // Enabling/resetting diagnostics must not manufacture a negative delta.
        guard now >= heldAt, !previous.contains(where: { scope, sample in
            counters[scope, default: .init()].evaluations < sample.evaluations
                || counters[scope, default: .init()].totalMilliseconds < sample.totalMilliseconds
        }) else { held = nil; heldAt = 0; return nil }
        var evaluations: [NTVRenderScope: Int] = [:]
        var filtering = 0.0
        for scope in NTVRenderScope.allCases {
            let current = counters[scope, default: .init()], old = previous[scope, default: .init()]
            evaluations[scope] = current.evaluations - old.evaluations
            if scope == .posterEligibility || scope == .searchPartition {
                filtering += current.totalMilliseconds - old.totalMilliseconds
            }
        }
        let sample = NTVNavigationSample(cadence: cadence, evaluations: evaluations,
                                         filteringMilliseconds: filtering)
        if held == nil || now - heldAt >= 15 || cadence.worstGapMilliseconds > (held?.cadence.worstGapMilliseconds ?? 0) {
            held = sample; heldAt = now
        }
        return held
    }
}

@MainActor private final class FrameMeterTarget: NSObject {
    weak var meter: FrameMeter?
    init(_ meter: FrameMeter) { self.meter = meter; super.init() }
    @objc func tick(_ link: CADisplayLink) { meter?.tick(link) }
}

/// Main-run-loop cadence, with interval outliers that an average rate hides.
@MainActor
final class FrameMeter: ObservableObject {
    @Published private(set) var snapshot = FrameCadenceSnapshot()
    @Published private(set) var navigationSample: NTVNavigationSample?
    var fps: Int { snapshot.callbacksPerSecond }
    /// The display's maximum refresh rate (60 on current Apple TV hardware),
    /// so the colour thresholds scale if that ever changes.
    let maxRefresh: Int = UIScreen.main.maximumFramesPerSecond

    private var link: CADisplayLink?
    private var cadence = FrameCadenceWindow()
    private var navigation = NTVNavigationWindow()
    private var needsNavigationBaseline = true

    func start() {
        guard link == nil else { return }
        cadence = FrameCadenceWindow()
        navigation = NTVNavigationWindow()
        needsNavigationBaseline = true
        navigationSample = nil
        // CADisplayLink retains its target. The weak relay lets a discarded
        // meter deallocate instead of retaining itself through its own link.
        let l = CADisplayLink(target: FrameMeterTarget(self), selector: #selector(FrameMeterTarget.tick(_:)))
        l.add(to: .main, forMode: .common)
        link = l
    }

    func stop() {
        link?.invalidate()
        link = nil
        cadence = FrameCadenceWindow()
        navigation = NTVNavigationWindow()
        navigationSample = nil
    }

    fileprivate func tick(_ link: CADisplayLink) {
        if needsNavigationBaseline {
            navigation = NTVNavigationWindow(baseline: NTVRenderProbe.snapshot())
            needsNavigationBaseline = false
        }
        let expected = max(link.targetTimestamp - link.timestamp, 1 / Double(max(maxRefresh, 1)))
        if let result = cadence.record(timestamp: link.timestamp, expectedInterval: expected) {
            navigationSample = navigation.record(cadence: result, counters: NTVRenderProbe.snapshot(),
                                                 now: link.timestamp)
            snapshot = result
        }
    }

    deinit { link?.invalidate() }
}
