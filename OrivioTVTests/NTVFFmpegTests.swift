import XCTest
import Libavcodec
import Libavformat
import Libavutil
@testable import OrivioTV

final class NTVFFmpegTests: XCTestCase {
    func testRequiredVideoAudioSubtitleAndContainerSupport() {
        XCTAssertEqual(NTVMediaDependencyAudit.ffmpegVersion, "6.1.6")
        for name in ["h264", "hevc", "aac", "ac3", "eac3", "dca", "truehd", "ass", "subrip", "pgssub", "webvtt"] {
            XCTAssertNotNil(avcodec_find_decoder_by_name(name), "Lost decoder: \(name)")
        }
        for name in ["mov", "matroska", "hls", "mpegts", "wav"] {
            XCTAssertNotNil(av_find_input_format(name), "Lost demuxer: \(name)")
        }
        let configuration = String(cString: avcodec_configuration())
        XCTAssertTrue(configuration.contains("--enable-videotoolbox"))
        XCTAssertTrue(configuration.contains("--enable-gnutls"))
    }

    func testActualFFmpegH264DecodeAndSeek() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "ntv-player-fixture", withExtension: "mp4"))
        var format: UnsafeMutablePointer<AVFormatContext>?
        XCTAssertEqual(avformat_open_input(&format, url.path, nil, nil), 0)
        let input = try XCTUnwrap(format)
        defer { avformat_close_input(&format) }
        XCTAssertGreaterThanOrEqual(avformat_find_stream_info(input, nil), 0)
        let index = av_find_best_stream(input, AVMEDIA_TYPE_VIDEO, -1, -1, nil, 0)
        XCTAssertGreaterThanOrEqual(index, 0)
        guard index >= 0 else { return }
        let stream = try XCTUnwrap(input.pointee.streams[Int(index)])
        let parameters = try XCTUnwrap(stream.pointee.codecpar)
        XCTAssertEqual(parameters.pointee.codec_id, AV_CODEC_ID_H264)
        let decoder = try XCTUnwrap(avcodec_find_decoder(parameters.pointee.codec_id))
        var context = avcodec_alloc_context3(decoder)
        let codec = try XCTUnwrap(context)
        defer { avcodec_free_context(&context) }
        XCTAssertEqual(avcodec_parameters_to_context(codec, parameters), 0)
        XCTAssertEqual(avcodec_open2(codec, decoder, nil), 0)
        var packet = av_packet_alloc(), frame = av_frame_alloc()
        let decoded = try XCTUnwrap(frame), encoded = try XCTUnwrap(packet)
        defer { av_packet_free(&packet); av_frame_free(&frame) }

        func readFrames(until target: Int64) -> (Int, Int64) {
            var count = 0, lastPTS: Int64 = -1
            for _ in 0..<1000 {
                guard av_read_frame(input, encoded) >= 0 else { break }
                defer { av_packet_unref(encoded) }
                guard encoded.pointee.stream_index == index else { continue }
                guard avcodec_send_packet(codec, encoded) >= 0 else { continue }
                while avcodec_receive_frame(codec, decoded) == 0 {
                    count += 1
                    XCTAssertGreaterThan(decoded.pointee.width, 0)
                    XCTAssertGreaterThan(decoded.pointee.height, 0)
                    lastPTS = decoded.pointee.best_effort_timestamp
                    av_frame_unref(decoded)
                    if count >= 3 && lastPTS >= target { return (count, lastPTS) }
                }
            }
            return (count, lastPTS)
        }
        let before = readFrames(until: 0)
        XCTAssertGreaterThanOrEqual(before.0, 3, "The new FFmpeg must decode real H264 frames.")
        let timebase = av_q2d(stream.pointee.time_base)
        XCTAssertGreaterThan(timebase, 0)
        guard timebase > 0 else { return }
        let target = Int64(2.0 / timebase)
        XCTAssertEqual(av_seek_frame(input, index, target, 1 /* AVSEEK_FLAG_BACKWARD */), 0)
        avcodec_flush_buffers(codec)
        let after = readFrames(until: target)
        XCTAssertGreaterThanOrEqual(after.0, 3)
        XCTAssertGreaterThanOrEqual(after.1, target, "Decode must reach the requested position after seeking.")
        XCTAssertGreaterThan(after.1, before.1)
    }
}
