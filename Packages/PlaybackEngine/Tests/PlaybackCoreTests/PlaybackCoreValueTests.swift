import Foundation
import Testing
@testable import PlaybackCore

@Suite("FourCC")
struct FourCCTests {
    @Test func roundTrips() {
        let code = FourCC("avc1")
        #expect(code.rawValue == 0x6176_6331)
        #expect(code.description == "avc1")
        #expect(FourCC(rawValue: 0x6176_6331) == "avc1")
    }

    @Test func padsShortCodes() {
        #expect(FourCC("aac").description == "aac ")
        #expect(FourCC("aac") == FourCC("aac "))
    }

    @Test func describesNonPrintableCodes() {
        #expect(FourCC(rawValue: 0).description == "0x00000000")
    }
}

@Suite("Container classification")
struct ContainerFormatTests {
    @Test func classifiesByExtension() {
        #expect(ContainerFormat(fileExtension: "MKV").support == .vlcOnly)
        #expect(ContainerFormat(fileExtension: "mkv").kindHint == .video)
        #expect(ContainerFormat(fileExtension: "flac").support == .native)
        #expect(ContainerFormat(fileExtension: "flac").kindHint == .audio)
        #expect(ContainerFormat(fileExtension: "opus").kindHint == .audio)
        #expect(ContainerFormat(fileExtension: "weird").support == .unknown)
        #expect(ContainerFormat(fileExtension: "").kindHint == .unknown)
    }

    @Test func detectsHLS() {
        #expect(ContainerFormat(url: URL(string: "https://x.test/live/master.m3u8")!).isHLSPlaylist)
    }
}

@Suite("Playback items")
struct PlaybackItemTests {
    @Test func derivesKindAndTitleFromURL() {
        let item = PlaybackItem(url: URL(fileURLWithPath: "/Movies/The.Grand.Budapest.Hotel_2014.mkv"))
        #expect(item.kind == .video)
        #expect(item.title == "The Grand Budapest Hotel 2014")
    }

    @Test func keepsExplicitValues() {
        let item = PlaybackItem(url: URL(fileURLWithPath: "/a/b.bin"), kind: .audio, title: "Custom")
        #expect(item.kind == .audio)
        #expect(item.title == "Custom")
    }

    @Test func titlesForStreams() {
        #expect(PlaybackItem.displayTitle(for: URL(string: "https://radio.example.com/")!) == "radio.example.com")
        #expect(PlaybackItem.displayTitle(for: URL(string: "rtsp://cam.local/live_stream.sdp")!) == "live stream")
    }
}

@Suite("Engine configuration")
struct EngineConfigurationTests {
    @Test func parsesShellLikeOptions() {
        #expect(EngineConfiguration.parseOptions("") == [])
        #expect(EngineConfiguration.parseOptions("  --a   --b=1 ") == ["--a", "--b=1"])
        #expect(EngineConfiguration.parseOptions(#"--sub-font="Helvetica Neue" :start-time=5"#) == ["--sub-font=Helvetica Neue", ":start-time=5"])
        #expect(EngineConfiguration.parseOptions(#"--x='a b' --y=c\ d"#) == ["--x=a b", "--y=c d"])
        #expect(EngineConfiguration.parseOptions(#"--empty="""#) == ["--empty="])
    }

    @Test func buildsLibraryAndMediaOptions() {
        var configuration = EngineConfiguration(networkCachingMilliseconds: 3_000, customLibVLCOptions: "--audio-time-stretch :sub-track=1 junk")
        #expect(configuration.libVLCLibraryOptions == ["--no-play-and-pause", "--network-caching=3000", "--audio-time-stretch"])
        #expect(configuration.libVLCMediaOptions == [":sub-track=1"])

        configuration.hardwareDecoding = false
        #expect(configuration.libVLCMediaOptions.prefix(2) == [":codec=avcodec,all", ":avcodec-hw=none"])
    }
}

@Suite("Track names")
struct MediaTrackTests {
    let english = Locale(identifier: "en_US")

    @Test func usesLanguageNames() {
        let track = MediaTrack(id: "1", kind: .audio, name: "Track 1 - [English]", languageCode: "en", channelCount: 6)
        #expect(track.displayName(locale: english) == "English \u{00B7} 5.1")
    }

    @Test func marksSDHAndForced() {
        let sdh = MediaTrack(id: "2", kind: .subtitle, name: "English SDH", languageCode: "eng")
        #expect(sdh.isSDH)
        #expect(sdh.displayName(locale: english) == "English (SDH)")

        let forced = MediaTrack(id: "3", kind: .subtitle, name: "Forced", languageCode: "fr")
        #expect(forced.displayName(locale: english) == "French (Forced)")
    }

    @Test func fallsBackToCleanedEngineNames() {
        let track = MediaTrack(id: "4", kind: .audio, name: "Track 2 - Director's Commentary [und]", languageCode: "und")
        #expect(track.displayName(locale: english) == "Director's Commentary")
        let unnamed = MediaTrack(id: "5", kind: .subtitle, name: "")
        #expect(unnamed.displayName(locale: english) == "Subtitle")
    }

    @Test func matchesLanguagesAcrossEngines() {
        // AVFoundation reports BCP-47, VLC usually ISO 639-2.
        #expect(MediaTrack.languagesMatch("en-US", "eng"))
        #expect(MediaTrack.languagesMatch("fra", "fr"))
        #expect(MediaTrack.languagesMatch("fre", "fr-CA"))
        #expect(MediaTrack.languagesMatch("ger", "deu"))
        #expect(MediaTrack.languagesMatch("pt-BR", "por"))
        #expect(!MediaTrack.languagesMatch("en", "ja"))
        #expect(!MediaTrack.languagesMatch(nil, "en"))
        #expect(!MediaTrack.languagesMatch("", ""))
        #expect(MediaTrack.normalizedLanguageCode("JPN") == "ja")
    }

    @Test func channelLayouts() {
        #expect(MediaTrack.channelLayoutName(1) == "Mono")
        #expect(MediaTrack.channelLayoutName(2) == "Stereo")
        #expect(MediaTrack.channelLayoutName(8) == "7.1")
        #expect(MediaTrack.channelLayoutName(nil) == nil)
    }
}

@Suite("Time formatting")
struct PlaybackTimeFormatterTests {
    @Test func formatsLikeApplePlayers() {
        #expect(PlaybackTimeFormatter.string(from: 7) == "0:07")
        #expect(PlaybackTimeFormatter.string(from: 754) == "12:34")
        #expect(PlaybackTimeFormatter.string(from: 3_723) == "1:02:03")
        #expect(PlaybackTimeFormatter.string(from: 7, referenceDuration: 5_400) == "0:00:07")
        #expect(PlaybackTimeFormatter.string(from: -3) == "0:00")
        #expect(PlaybackTimeFormatter.string(from: .nan) == "--:--")
    }

    @Test func formatsRemainingTime() {
        #expect(PlaybackTimeFormatter.remainingString(currentTime: 10, duration: 306) == "-4:56")
        #expect(PlaybackTimeFormatter.remainingString(currentTime: 400, duration: 306) == "-0:00")
    }

    @Test func spokenForm() {
        #expect(PlaybackTimeFormatter.accessibilityString(from: 3_723) == "1 hour, 2 minutes, 3 seconds")
        #expect(PlaybackTimeFormatter.accessibilityString(from: 0) == "0 seconds")
        #expect(PlaybackTimeFormatter.accessibilityString(from: 61) == "1 minute, 1 second")
    }
}

@Suite("Video dimensions")
struct VideoDimensionsTests {
    @Test func badges() {
        #expect(VideoDimensions(width: 3840, height: 2160).resolutionBadge == "4K")
        #expect(VideoDimensions(width: 3840, height: 1600).resolutionBadge == "4K")
        #expect(VideoDimensions(width: 1920, height: 800).resolutionBadge == "1080p")
        #expect(VideoDimensions(width: 1280, height: 720).resolutionBadge == "720p")
        #expect(VideoDimensions(width: 720, height: 576).resolutionBadge == "SD")
        #expect(VideoDimensions(width: 1920, height: 1080).aspectRatio > 1.77)
    }
}
