import AVFoundation
import Foundation
#if os(macOS)
import CoreAudio
#else
import UIKit
#endif

#if os(macOS)
var property = AudioObjectPropertyAddress(
    mSelector: kAudioHardwarePropertyDefaultOutputDevice,
    mScope: kAudioObjectPropertyScopeGlobal,
    mElement: kAudioObjectPropertyElementMain)
var output = AudioDeviceID(kAudioObjectUnknown)
var size = UInt32(MemoryLayout<AudioDeviceID>.size)
let audioStatus = AudioObjectGetPropertyData(
    AudioObjectID(kAudioObjectSystemObject), &property, 0, nil, &size, &output)
print("host_audio_query_status=\(audioStatus) host_output_available=\(output != kAudioObjectUnknown)")
#endif

func probe(_ asset: AVAsset, label: String) -> Bool {
    let item = AVPlayerItem(asset: asset)
    let player = AVPlayer(playerItem: item)
    player.play()
    defer { player.pause() }
    let deadline = Date().addingTimeInterval(15)
    while item.status == .unknown && Date() < deadline {
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    }
    if item.status == .readyToPlay {
        RunLoop.main.run(until: Date().addingTimeInterval(2))
    }
    let error = item.error as NSError?
    let advanced = player.currentTime().seconds > 0.1
    print("\(label) status=\(item.status.rawValue) advanced=\(advanced) error_domain=\(error?.domain ?? "none") error_code=\(error?.code ?? 0)")
    return item.status == .readyToPlay && advanced
}

func runProbes() {
    let path = CommandLine.arguments.dropFirst().first
        ?? Bundle.main.path(forResource: "ntv-player-fixture", ofType: "mp4") ?? ""
    guard FileManager.default.fileExists(atPath: path) else { fatalError("Missing local fixture") }
    let asset = AVURLAsset(url: URL(fileURLWithPath: path))
    let audiovisualPassed = probe(asset, label: "audiovisual")
    let videoOnly = AVMutableComposition()
    // This control isolates audio initialization; it never changes nTV's fixture.
    guard let source = asset.tracks(withMediaType: .video).first,
          let track = videoOnly.addMutableTrack(withMediaType: .video,
                                                preferredTrackID: kCMPersistentTrackID_Invalid) else {
        fatalError("Missing video control track")
    }
    do {
        try track.insertTimeRange(CMTimeRange(start: .zero, duration: asset.duration), of: source, at: .zero)
    } catch { fatalError("Cannot create video control track") }
    let videoPassed = probe(videoOnly, label: "video_only")
    exit(audiovisualPassed && videoPassed ? 0 : 1)
}

#if os(macOS)
runProbes()
#else
final class MediaProbeDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    private var started = false
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        window = UIWindow(frame: UIScreen.main.bounds)
        window?.rootViewController = UIViewController()
        window?.makeKeyAndVisible()
        return true
    }
    func applicationDidBecomeActive(_ application: UIApplication) {
        guard !started else { return }
        started = true
        DispatchQueue.main.async { runProbes() }
    }
}
UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, nil, NSStringFromClass(MediaProbeDelegate.self))
#endif
