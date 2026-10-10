import AVKit
import SwiftUI

struct NTVTwitchPlaybackTarget: Identifiable {
    let login: String
    let name: String
    let title: String
    var id: String { login }
}

struct NTVTwitchPlayer: View {
    let target: NTVTwitchPlaybackTarget
    let scope: String
    let close: () -> Void
    @StateObject private var model = NTVTwitchPlayerModel()
    @State private var retry = 0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let player = model.player {
                NTVTwitchVideo(player: player, qualities: model.qualities,
                               selected: model.selectedQuality, select: model.selectQuality)
                    .ignoresSafeArea()
                    .accessibilityIdentifier(model.ready ? "ntv.twitch.player.video" : "ntv.twitch.player.preparing-video")
            }
            if model.message != nil || model.player == nil {
                VStack(spacing: 26) {
                    Text(target.name).font(.system(size: 40, weight: .semibold))
                        .accessibilityIdentifier("ntv.twitch.player.heading")
                    if let message = model.message {
                        Text(message).font(.system(size: 25)).multilineTextAlignment(.center)
                            .frame(maxWidth: 900).accessibilityIdentifier("ntv.twitch.player.error")
                        Button("Réessayer") { retry += 1 }
                            .buttonStyle(NTVActionButtonStyle())
                            .accessibilityIdentifier("ntv.twitch.player.retry")
                    } else { ProgressView("Préparation du direct…") }
                    Button("Fermer", action: close).buttonStyle(NTVActionButtonStyle())
                }
                .foregroundStyle(.white)
            }
        }
        .task(id: "\(scope)/\(target.login)/\(retry)") { await model.load(target) }
        .onDisappear { model.stop() }
        .onExitCommand(perform: close)
    }
}

@MainActor final class NTVTwitchPlayerModel: ObservableObject {
    @Published private(set) var player: AVPlayer?
    @Published private(set) var message: String?
    @Published private(set) var ready = false
    @Published private(set) var qualities: [NTVTwitchQuality] = []
    @Published private(set) var selectedQuality: String?
    private var media: NTVTwitchMedia?
    private var target: NTVTwitchPlaybackTarget?
    private var observation: NSKeyValueObservation?
    private var version = 0
    private let resolve: (String) async throws -> NTVTwitchMedia

    init(resolve: ((String) async throws -> URL)? = nil,
         mediaResolver: ((String) async throws -> NTVTwitchMedia)? = nil) {
        if let mediaResolver { self.resolve = mediaResolver }
        else if let resolve { self.resolve = { .init(masterURL: try await resolve($0), qualities: []) } }
        else { self.resolve = { try await NTVTwitchPlayerModel.defaultResolve($0) } }
    }

    func load(_ target: NTVTwitchPlaybackTarget) async {
        stop()
        let request = version
        do {
            let resolved = try await resolve(target.login)
            try Task.checkCancellation()
            guard request == version else { return }
            media = resolved
            self.target = target
            qualities = resolved.qualities
            let current = AVPlayer()
            player = current
            replaceItem(url: resolved.masterURL, target: target, request: request)
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try? AVAudioSession.sharedInstance().setActive(true)
            current.play()
        } catch {
            guard request == version, !Task.isCancelled, !(error is CancellationError) else { return }
            message = (error as? NTVTwitchPlayback.Failure)?.errorDescription
                ?? "La lecture Twitch est momentanément indisponible. Réessayez."
        }
    }

    func selectQuality(_ identifier: String?) {
        guard let media, let target, let player, identifier != selectedQuality else { return }
        let url: URL
        if let identifier {
            guard let quality = qualities.first(where: { $0.id == identifier }) else { return }
            url = quality.url
        } else { url = media.masterURL }
        let wasPlaying = player.rate > 0 || player.timeControlStatus == .waitingToPlayAtSpecifiedRate
        version &+= 1
        selectedQuality = identifier
        message = nil
        ready = false
        // Preserve the AVKit controller and its controls while changing only
        // the HLS item. A live rendition resumes at its live edge.
        replaceItem(url: url, target: target, request: version)
        if wasPlaying { player.play() }
    }

    private func replaceItem(url: URL, target: NTVTwitchPlaybackTarget, request: Int) {
            observation?.invalidate()
            let item = AVPlayerItem(url: url)
            item.preferredForwardBufferDuration = 3
            let metadata = AVMutableMetadataItem()
            metadata.identifier = .commonIdentifierTitle
            metadata.value = "\(target.name) · \(target.title)" as NSString
            item.externalMetadata = [metadata]
            player?.replaceCurrentItem(with: item)
            observation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
                Task { @MainActor [weak self] in
                    guard let self, request == self.version, self.player?.currentItem === item else { return }
                    if item.status == .readyToPlay { self.ready = true }
                    else if item.status == .failed {
                        self.ready = false
                        // Never expose AVFoundation errors: their URLs contain a
                        // short-lived signed video token and may reveal IP data.
                        self.message = "Le direct ne peut pas être lu. Réessayez."
                        self.player?.pause()
                    }
                }
            }
    }

    func stop() {
        version &+= 1
        observation?.invalidate(); observation = nil
        ready = false
        player?.pause(); player?.replaceCurrentItem(with: nil); player = nil
        message = nil
        media = nil; target = nil; qualities = []; selectedQuality = nil
    }

    private static func defaultResolve(_ login: String) async throws -> NTVTwitchMedia {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ntvTwitchDemo") {
            guard let fixture = Bundle.main.url(forResource: "ntv-player-fixture", withExtension: "mp4") else {
                throw NTVTwitchPlayback.Failure.unavailable
            }
            return .init(masterURL: fixture, qualities: [
                .init(id: "fixture-1080", label: "1080p60", url: fixture, height: 1080, frameRate: 60, bandwidth: 6000000),
                .init(id: "fixture-720", label: "720p60", url: fixture, height: 720, frameRate: 60, bandwidth: 3000000)
            ])
        }
        #endif
        return try await NTVTwitchPlayback().resolveMedia(channel: login)
    }
}

private struct NTVTwitchVideo: UIViewControllerRepresentable {
    let player: AVPlayer
    let qualities: [NTVTwitchQuality]
    let selected: String?
    let select: (String?) -> Void
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = true
        controller.allowsPictureInPicturePlayback = false
        controller.videoGravity = .resizeAspect
        updateMenu(controller)
        return controller
    }
    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player { controller.player = player }
        updateMenu(controller)
    }
    private func updateMenu(_ controller: AVPlayerViewController) {
        let automatic = UIAction(title: "Automatique", state: selected == nil ? .on : .off) { _ in select(nil) }
        let choices = qualities.map { quality in
            UIAction(title: quality.label, state: selected == quality.id ? .on : .off) { _ in select(quality.id) }
        }
        controller.transportBarCustomMenuItems = [UIMenu(title: "Qualité",
            image: UIImage(systemName: "gearshape"), options: .singleSelection, children: [automatic] + choices)]
    }
    static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: ()) {
        controller.player?.pause()
        controller.player = nil
    }
}
