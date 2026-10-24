import SwiftUI

/// The in-player diagnostics HUD (Settings → Performance → Developer).
///
/// One glance answers the questions that otherwise need a Mac attached: which
/// engine is playing, at what fps, how many frames it has dropped, how far
/// audio and video have drifted, what the stream's real bitrate is and how
/// deep the read-ahead buffer sits. Polls once a second — cheap enough to
/// leave on while chasing a stutter, and it never eats focus.
struct PlayerDiagnosticsHUD: View {
    @ObservedObject var viewModel: PlayerViewModel
    @State private var snapshot = PlayerViewModel.DiagnosticsSnapshot()
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // The HUD names itself and its off-switch. Left on after a
            // debugging session, an unlabeled stat block over the letterbox
            // bar reads as rendering garbage, not as a tool ("top black
            // border was showing some garbage").
            Text("DIAGNOSTICS · Réglages → Performance")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.45))
                .padding(.bottom, 2)
            row("Moteur", snapshot.engine)
            row("Cadence", snapshot.fps.map { String(format: "%.1f i/s", $0) } ?? "Indisponible",
                bad: snapshot.fps.map { $0 < 22 } ?? false)
            row("Images perdues", snapshot.droppedFrames.map { String($0) } ?? "Indisponible",
                bad: snapshot.droppedFrames.map { $0 > 30 } ?? false)
            row("Décalage A/V", snapshot.avSyncDiff.map { String(format: "%+.0f ms", $0 * 1000) } ?? "Indisponible",
                bad: snapshot.avSyncDiff.map { abs($0) > 0.12 } ?? false)
            row("Débit", snapshot.bitrateMbps.map { String(format: "%.1f Mbit/s", $0) } ?? "Indisponible")
            row("Tampon", snapshot.bufferSeconds.map { String(format: "%.0f s d’avance", $0) } ?? "Indisponible",
                bad: snapshot.bufferSeconds.map { $0 < 2 } ?? false)
            row("Données lues", snapshot.downloadedMB.map { String(format: "%.0f Mo", $0) } ?? "Indisponible")
        }
        .font(.system(size: 20, weight: .semibold, design: .monospaced))
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.72)))
        .padding(.top, 40)
        .padding(.leading, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
        .onAppear { snapshot = viewModel.diagnosticsSnapshot() }
        .onReceive(tick) { _ in snapshot = viewModel.diagnosticsSnapshot() }
    }

    @ViewBuilder private func row(_ label: String, _ value: String, bad: Bool = false) -> some View {
        HStack(spacing: 10) {
            Text(label).foregroundStyle(.white.opacity(0.6))
            Spacer(minLength: 0)
            Text(value).foregroundStyle(bad ? Color.red : .white)
        }
        .frame(width: 420)
    }
}
