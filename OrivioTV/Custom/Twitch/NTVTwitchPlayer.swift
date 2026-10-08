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
                NTVTwitchVideo(player: player)
                    .ignoresSafeArea()
                    .accessibilityIdentifier(model.ready ? "ntv.twitch.player.video" : "ntv.twitch.player.preparing-video")
            }
            if model.message != nil || !model.ready {
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
    private var observation: NSKeyValueObservation?
    private var version = 0
    private let resolve: (String) async throws -> URL

    init(resolve: ((String) async throws -> URL)? = nil) {
        self.resolve = resolve ?? { try await NTVTwitchPlayerModel.defaultResolve($0) }
    }

    func load(_ target: NTVTwitchPlaybackTarget) async {
        stop()
        let request = version
        do {
            let url = try await resolve(target.login)
            try Task.checkCancellation()
            guard request == version else { return }
            let item = AVPlayerItem(url: url)
            item.preferredForwardBufferDuration = 3
            let metadata = AVMutableMetadataItem()
            metadata.identifier = .commonIdentifierTitle
            metadata.value = "\(target.name) · \(target.title)" as NSString
            item.externalMetadata = [metadata]
            let current = AVPlayer(playerItem: item)
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try? AVAudioSession.sharedInstance().setActive(true)
            player = current
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
            current.play()
        } catch {
            guard request == version, !Task.isCancelled, !(error is CancellationError) else { return }
            message = (error as? NTVTwitchPlayback.Failure)?.errorDescription
                ?? "La lecture Twitch est momentanément indisponible. Réessayez."
        }
    }

    func stop() {
        version &+= 1
        observation?.invalidate(); observation = nil
        ready = false
        player?.pause(); player?.replaceCurrentItem(with: nil); player = nil
        message = nil
    }

    private static func defaultResolve(_ login: String) async throws -> URL {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ntvTwitchDemo") {
            guard let fixture = Bundle.main.url(forResource: "ntv-player-fixture", withExtension: "mp4") else {
                throw NTVTwitchPlayback.Failure.unavailable
            }
            return fixture
        }
        #endif
        return try await NTVTwitchPlayback().resolve(channel: login)
    }
}

private struct NTVTwitchVideo: UIViewControllerRepresentable {
    let player: AVPlayer
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = true
        controller.allowsPictureInPicturePlayback = false
        controller.videoGravity = .resizeAspect
        return controller
    }
    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player { controller.player = player }
    }
    static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: ()) {
        controller.player?.pause()
        controller.player = nil
    }
}
