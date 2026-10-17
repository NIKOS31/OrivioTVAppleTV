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
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 12, height: 12)
            Text("UI \(meter.fps) Hz · max \(Int(meter.snapshot.worstGapMilliseconds.rounded())) ms · \(meter.snapshot.lateCallbacks) retards")
                .font(.system(size: 22, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Capsule().fill(Color.black.opacity(0.72)))
        .overlay(Capsule().strokeBorder(color.opacity(0.8), lineWidth: 2))
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

@MainActor private final class FrameMeterTarget: NSObject {
    weak var meter: FrameMeter?
    init(_ meter: FrameMeter) { self.meter = meter; super.init() }
    @objc func tick(_ link: CADisplayLink) { meter?.tick(link) }
}

/// Main-run-loop cadence, with interval outliers that an average rate hides.
@MainActor
final class FrameMeter: ObservableObject {
    @Published private(set) var snapshot = FrameCadenceSnapshot()
    var fps: Int { snapshot.callbacksPerSecond }
    /// The display's maximum refresh rate (60 on current Apple TV hardware),
    /// so the colour thresholds scale if that ever changes.
    let maxRefresh: Int = UIScreen.main.maximumFramesPerSecond

    private var link: CADisplayLink?
    private var cadence = FrameCadenceWindow()

    func start() {
        guard link == nil else { return }
        cadence = FrameCadenceWindow()
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
    }

    fileprivate func tick(_ link: CADisplayLink) {
        let expected = max(link.targetTimestamp - link.timestamp, 1 / Double(max(maxRefresh, 1)))
        if let result = cadence.record(timestamp: link.timestamp, expectedInterval: expected) {
            snapshot = result
        }
    }

    deinit { link?.invalidate() }
}
