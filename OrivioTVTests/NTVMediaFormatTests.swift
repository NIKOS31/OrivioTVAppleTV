import XCTest
import AVFoundation
import CryptoKit
import Libavcodec
import Libavformat
import Libavutil
@testable import OrivioTV

final class NTVMediaFormatTests: XCTestCase {
    private struct Fixture: Decodable {
        struct Expected: Decodable {
            let video: String?
            let audio: String?
            let width: Int?
            let height: Int?
            let rate: Int
            let depth: Int?
            let channels: Int?
            let primaries: String?
            let transfer: String?
        }
        let file: String
        let bytes: Int
        let sha256: String
        let expected: Expected
    }

    private func fixtures() throws -> [Fixture] {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "ntv-format-manifest", withExtension: "json", subdirectory: "Fixtures"))
        let values = try JSONDecoder().decode([Fixture].self, from: Data(contentsOf: url))
        XCTAssertEqual(values.count, 11)
        XCTAssertEqual(Set(values.map(\.file)).count, 11)
        return values
    }

    private func verifiedURL(_ fixture: Fixture) throws -> URL {
        let name = (fixture.file as NSString).deletingPathExtension
        let ext = (fixture.file as NSString).pathExtension
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: ext, subdirectory: "Fixtures"))
        let data = try Data(contentsOf: url)
        XCTAssertEqual(data.count, fixture.bytes, fixture.file)
        XCTAssertEqual(SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(), fixture.sha256, fixture.file)
        return url
    }

    @MainActor
    func testAVPlayerLoadsAndDecodesNativeMP4MOVAnd4K60HEVC10Fixtures() async throws {
        let native = try fixtures().filter { $0.expected.video != nil && ($0.file.hasSuffix(".mp4") || $0.file.hasSuffix(".mov")) }
        XCTAssertEqual(native.count, 3)
        for fixture in native {
            let asset = AVURLAsset(url: try verifiedURL(fixture))
            let tracks = try await asset.loadTracks(withMediaType: .video)
            let track = try XCTUnwrap(tracks.first, fixture.file)
            let rate = try await track.load(.nominalFrameRate)
            XCTAssertEqual(rate, Float(fixture.expected.rate), accuracy: 0.1, fixture.file)
            let formats = try await track.load(.formatDescriptions)
            let format = try XCTUnwrap(formats.first)
            XCTAssertEqual(CMFormatDescriptionGetMediaSubType(format),
                           fixture.expected.video == "hevc" ? kCMVideoCodecType_HEVC : kCMVideoCodecType_H264, fixture.file)
            let item = AVPlayerItem(asset: asset)
            let ready = expectation(description: fixture.file + " native preparation")
            let observation = item.observe(\.status, options: [.initial, .new]) { item, _ in
                if item.status != .unknown { ready.fulfill() }
            }
            let player = AVPlayer(playerItem: item)
            defer { observation.invalidate(); player.pause(); player.replaceCurrentItem(with: nil) }
            player.play()
            await fulfillment(of: [ready], timeout: 15)
            XCTAssertEqual(item.status, .readyToPlay, fixture.file)
            let generator = AVAssetImageGenerator(asset: asset)
            let (image, _) = try await generator.image(at: CMTime(seconds: 0.5, preferredTimescale: 600))
            XCTAssertEqual(image.width, fixture.expected.width, fixture.file)
            XCTAssertEqual(image.height, fixture.expected.height, fixture.file)
        }
    }

    func testShippedFFmpegDecodesAndSeeksMP4MKVMOVTSIncluding4K60HEVC10() throws {
        let video = try fixtures().filter { $0.expected.video != nil }
        XCTAssertEqual(video.count, 5)
        for fixture in video { try decodeAndSeek(fixture, mediaType: AVMEDIA_TYPE_VIDEO) }
    }

    func testShippedFFmpegDecodesAndSeeksSixChannelAACAC3EAC3FLACTrueHDAndDTS() throws {
        let audio = try fixtures().filter { $0.expected.video == nil }
        XCTAssertEqual(audio.count, 6)
        for fixture in audio { try decodeAndSeek(fixture, mediaType: AVMEDIA_TYPE_AUDIO) }
    }

    private func decodeAndSeek(_ fixture: Fixture, mediaType: Libavutil.AVMediaType) throws {
        let url = try verifiedURL(fixture)
        var format: UnsafeMutablePointer<AVFormatContext>?
        XCTAssertEqual(avformat_open_input(&format, url.path, nil, nil), 0, fixture.file)
        let input = try XCTUnwrap(format)
        defer { avformat_close_input(&format) }
        XCTAssertGreaterThanOrEqual(avformat_find_stream_info(input, nil), 0, fixture.file)
        let index = av_find_best_stream(input, mediaType, -1, -1, nil, 0)
        XCTAssertGreaterThanOrEqual(index, 0, fixture.file)
        guard index >= 0 else { return }
        let stream = try XCTUnwrap(input.pointee.streams[Int(index)])
        let parameters = try XCTUnwrap(stream.pointee.codecpar)
        XCTAssertEqual(String(cString: avcodec_get_name(parameters.pointee.codec_id)),
                       mediaType == AVMEDIA_TYPE_VIDEO ? fixture.expected.video : fixture.expected.audio, fixture.file)
        let decoder = try XCTUnwrap(avcodec_find_decoder(parameters.pointee.codec_id))
        var context = avcodec_alloc_context3(decoder)
        let codec = try XCTUnwrap(context)
        defer { avcodec_free_context(&context) }
        XCTAssertEqual(avcodec_parameters_to_context(codec, parameters), 0, fixture.file)
        XCTAssertEqual(avcodec_open2(codec, decoder, nil), 0, fixture.file)
        var packet = av_packet_alloc(), frame = av_frame_alloc()
        let encoded = try XCTUnwrap(packet), decoded = try XCTUnwrap(frame)
        defer { av_packet_free(&packet); av_frame_free(&frame) }

        func readFrames(until target: Int64) throws -> (Int, Int64) {
            var count = 0, lastPTS: Int64 = .min
            for _ in 0..<6000 {
                guard av_read_frame(input, encoded) >= 0 else { break }
                defer { av_packet_unref(encoded) }
                guard encoded.pointee.stream_index == index else { continue }
                XCTAssertGreaterThanOrEqual(avcodec_send_packet(codec, encoded), 0, fixture.file)
                while avcodec_receive_frame(codec, decoded) == 0 {
                    count += 1
                    lastPTS = decoded.pointee.best_effort_timestamp
                    if mediaType == AVMEDIA_TYPE_VIDEO {
                        XCTAssertEqual(Int(decoded.pointee.width), fixture.expected.width, fixture.file)
                        XCTAssertEqual(Int(decoded.pointee.height), fixture.expected.height, fixture.file)
                        if let depth = fixture.expected.depth {
                            let description = try XCTUnwrap(av_pix_fmt_desc_get(codec.pointee.pix_fmt))
                            XCTAssertGreaterThanOrEqual(Int(description.pointee.comp.0.depth), depth, fixture.file)
                        }
                        if fixture.expected.primaries == "bt2020" {
                            XCTAssertEqual(decoded.pointee.color_primaries, AVCOL_PRI_BT2020, fixture.file)
                        }
                        if fixture.expected.transfer == "smpte2084" {
                            XCTAssertEqual(decoded.pointee.color_trc, AVCOL_TRC_SMPTE2084, fixture.file)
                        }
                    } else {
                        XCTAssertEqual(Int(decoded.pointee.ch_layout.nb_channels), fixture.expected.channels, fixture.file)
                        XCTAssertEqual(Int(decoded.pointee.sample_rate), fixture.expected.rate, fixture.file)
                        XCTAssertGreaterThan(decoded.pointee.nb_samples, 0, fixture.file)
                    }
                    av_frame_unref(decoded)
                    if count >= 3 && lastPTS >= target { return (count, lastPTS) }
                }
            }
            return (count, lastPTS)
        }
        let start = stream.pointee.start_time == Int64.min ? 0 : stream.pointee.start_time
        let before = try readFrames(until: start)
        XCTAssertGreaterThanOrEqual(before.0, 3, fixture.file)
        let timebase = av_q2d(stream.pointee.time_base)
        XCTAssertGreaterThan(timebase, 0, fixture.file)
        guard timebase > 0 else { return }
        let target = start + Int64(1 / timebase)
        XCTAssertEqual(av_seek_frame(input, index, target, 1 /* AVSEEK_FLAG_BACKWARD */), 0, fixture.file)
        avcodec_flush_buffers(codec)
        let after = try readFrames(until: target)
        XCTAssertGreaterThanOrEqual(after.0, 3, fixture.file)
        XCTAssertGreaterThanOrEqual(after.1, target, fixture.file)
        XCTAssertGreaterThan(after.1, before.1, fixture.file)
    }
}
