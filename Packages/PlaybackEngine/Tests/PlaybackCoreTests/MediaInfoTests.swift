import Foundation
import Testing
@testable import PlaybackCore

@Suite("Media info")
struct MediaInfoTests {
    @Test func namesCodecsFromEitherEngine() {
        // AVFoundation codes and libVLC's own codes.
        #expect(CodecNames.name(for: "avc1") == "H.264")
        #expect(CodecNames.name(for: "h264") == "H.264")
        #expect(CodecNames.name(for: "hvc1") == "HEVC")
        #expect(CodecNames.name(for: "ec-3") == "Dolby Digital Plus")
        #expect(CodecNames.name(for: "a52 ") == "Dolby Digital")
        #expect(CodecNames.name(for: "mlp ") == "Dolby TrueHD")
        #expect(CodecNames.name(for: "VP90") == "VP9")
        #expect(CodecNames.name(for: "spu ") == "DVD (VobSub)")
        #expect(CodecNames.name(for: "zzzz") == nil)
    }

    @Test func formatsFigures() {
        #expect(MediaInfoFormat.bitrate(640_000) == "640 kb/s")
        #expect(MediaInfoFormat.bitrate(4_500_000) == "4.5 Mb/s")
        #expect(MediaInfoFormat.frameRate(24_000.0 / 1_001.0) == "23.976 fps")
        #expect(MediaInfoFormat.frameRate(25) == "25 fps")
        #expect(MediaInfoFormat.sampleRate(48_000) == "48 kHz")
        #expect(MediaInfoFormat.sampleRate(44_100) == "44.1 kHz")
        #expect(MediaInfoFormat.channels(6) == "5.1")
        #expect(MediaInfoFormat.channels(3) == "3 channels")
    }

    @Test func namesStreams() {
        let english = Locale(identifier: "en_US")
        let commentary = MediaInfo.Stream(id: "a", kind: .audio, language: "eng", title: "Commentary")
        #expect(commentary.displayName(index: 1, locale: english) == "English \u{00B7} Commentary")
        let bare = MediaInfo.Stream(id: "b", kind: .audio)
        #expect(bare.displayName(index: 2, locale: english) == "Track 3")
        let info = MediaInfo(streams: [commentary, bare, MediaInfo.Stream(id: "v", kind: .video)])
        #expect(info.audio.count == 2 && info.video.count == 1 && info.subtitles.isEmpty)
    }

    @Test func namesContainers() {
        #expect(ContainerFormat(fileExtension: "mkv").displayName == "Matroska")
        #expect(ContainerFormat(fileExtension: "MOV").displayName == "QuickTime")
        #expect(ContainerFormat(fileExtension: "iso").displayName == "Disc Image")
        #expect(ContainerFormat(fileExtension: "xyz").displayName == nil)
    }
}
