import AVFoundation
import CoreAudio
import Foundation

var property = AudioObjectPropertyAddress(
    mSelector: kAudioHardwarePropertyDefaultOutputDevice,
    mScope: kAudioObjectPropertyScopeGlobal,
    mElement: kAudioObjectPropertyElementMain)
var output = AudioDeviceID(kAudioObjectUnknown)
var size = UInt32(MemoryLayout<AudioDeviceID>.size)
let audioStatus = AudioObjectGetPropertyData(
    AudioObjectID(kAudioObjectSystemObject), &property, 0, nil, &size, &output)
print("host_audio_query_status=\(audioStatus) host_output_available=\(output != kAudioObjectUnknown)")

let path = CommandLine.arguments.dropFirst().first ?? ""
guard FileManager.default.fileExists(atPath: path) else { fatalError("Missing local fixture") }
let asset = AVURLAsset(url: URL(fileURLWithPath: path))

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

let audiovisualPassed = probe(asset, label: "host_audiovisual")
let videoOnly = AVMutableComposition()
// This control isolates audio initialization; it never changes nTV's fixture.
guard let source = asset.tracks(withMediaType: .video).first,
      let track = videoOnly.addMutableTrack(withMediaType: .video,
                                            preferredTrackID: kCMPersistentTrackID_Invalid) else {
    fatalError("Missing video control track")
}
try track.insertTimeRange(CMTimeRange(start: .zero, duration: asset.duration), of: source, at: .zero)
let videoPassed = probe(videoOnly, label: "host_video_only")
exit(audiovisualPassed && videoPassed ? 0 : 1)
