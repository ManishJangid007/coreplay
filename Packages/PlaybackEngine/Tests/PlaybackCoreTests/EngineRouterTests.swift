import Foundation
import Testing
@testable import PlaybackCore

@Suite("Engine routing")
struct EngineRouterTests {
    let router = EngineRouter()

    private func item(_ path: String, preference: EnginePreference = .automatic, subtitles: [URL] = []) -> PlaybackItem {
        let url = path.contains("://") ? URL(string: path)! : URL(fileURLWithPath: path)
        return PlaybackItem(url: url, enginePreference: preference, externalSubtitleURLs: subtitles)
    }

    private func probe(_ tracks: [(MediaProbe.Track.Kind, FourCC)], playable: Bool = true) -> MediaProbe {
        MediaProbe(
            isPlayable: playable,
            tracks: tracks.map { MediaProbe.Track(kind: $0.0, codec: $0.1, isPlayable: true) }
        )
    }

    // MARK: Quick decisions

    @Test("VLC-only containers skip probing", arguments: ["mkv", "avi", "wmv", "flv", "webm", "ogg", "opus", "ts", "vob", "iso", "ape"])
    func vlcOnlyContainers(ext: String) {
        let decision = router.quickDecision(for: item("/media/file.\(ext)"))
        #expect(decision?.engine == .vlc)
        #expect(decision?.reason == .unsupportedContainer(ext))
    }

    @Test("Native containers need a probe", arguments: ["mp4", "mov", "m4v", "m4a", "mp3", "flac", "wav"])
    func nativeContainersNeedProbe(ext: String) {
        #expect(router.quickDecision(for: item("/media/file.\(ext)")) == nil)
    }

    @Test func itemOverridesWin() {
        #expect(router.quickDecision(for: item("/a.mp4", preference: .vlc))?.engine == .vlc)
        #expect(router.quickDecision(for: item("/a.mkv", preference: .avFoundation))?.engine == .avFoundation)
        #expect(router.quickDecision(for: item("/a.mkv", preference: .avFoundation))?.reason == .itemOverride)
    }

    @Test func alwaysUseVLCSetting() {
        let vlcRouter = EngineRouter(alwaysUseVLC: true)
        let decision = vlcRouter.quickDecision(for: item("/movie.mp4"))
        #expect(decision == .init(engine: .vlc, reason: .alwaysUseVLCSetting))
        // A per-item preference still beats the global setting.
        #expect(vlcRouter.quickDecision(for: item("/movie.mp4", preference: .avFoundation))?.engine == .avFoundation)
    }

    @Test("Non-HTTP network protocols go to VLC", arguments: ["rtsp://cam.local/stream", "smb://nas/movies/a.mp4", "udp://@239.0.0.1:1234", "ftp://host/a.mp3", "rtmp://live/app"])
    func networkProtocols(url: String) {
        let decision = router.quickDecision(for: item(url))
        #expect(decision?.engine == .vlc)
        if case .networkProtocol = decision?.reason {} else {
            Issue.record("Expected a network protocol reason, got \(String(describing: decision?.reason))")
        }
    }

    @Test func httpStreams() {
        #expect(router.quickDecision(for: item("https://example.com/live/index.m3u8"))?.engine == .avFoundation)
        #expect(router.quickDecision(for: item("https://example.com/video.mp4"))?.engine == .avFoundation)
        #expect(router.quickDecision(for: item("https://example.com/video.mkv"))?.engine == .vlc)
        #expect(router.quickDecision(for: item("http://radio.example.com:8000/stream"))?.engine == .vlc)
    }

    @Test func externalSubtitlesNeedVLC() {
        let subtitle = URL(fileURLWithPath: "/media/movie.en.srt")
        let decision = router.quickDecision(for: item("/media/movie.mp4", subtitles: [subtitle]))
        #expect(decision == .init(engine: .vlc, reason: .externalSubtitles))
    }

    // MARK: Probe-based decisions

    @Test func h264AACMP4PlaysWithAVFoundation() {
        let decision = router.decision(for: item("/movie.mp4"), probe: probe([(.video, "avc1"), (.audio, "mp4a"), (.text, "tx3g")]))
        #expect(decision == .init(engine: .avFoundation, reason: .nativelySupported))
    }

    @Test func hevcDolbyVisionWithAtmosPlaysWithAVFoundation() {
        let decision = router.decision(for: item("/movie.mp4"), probe: probe([(.video, "dvh1"), (.audio, "ec-3"), (.auxiliary, "tmcd")]))
        #expect(decision.engine == .avFoundation)
    }

    @Test func dtsAudioNeedsVLC() {
        let decision = router.decision(for: item("/movie.mp4"), probe: probe([(.video, "avc1"), (.audio, "dtsc")]))
        #expect(decision == .init(engine: .vlc, reason: .unsupportedAudioCodec("dtsc")))
    }

    @Test func av1NeedsVLC() {
        let decision = router.decision(for: item("/movie.mp4"), probe: probe([(.video, "av01"), (.audio, "mp4a")]))
        #expect(decision == .init(engine: .vlc, reason: .unsupportedVideoCodec("av01")))
    }

    @Test func pgsSubtitlesInMP4NeedVLC() {
        let decision = router.decision(for: item("/movie.mp4"), probe: probe([(.video, "avc1"), (.audio, "mp4a"), (.text, "pgs ")]))
        #expect(decision.engine == .vlc)
    }

    @Test func unplayableTrackNeedsVLC() {
        let tracks = [
            MediaProbe.Track(kind: .video, codec: "hvc1", isPlayable: false),
            MediaProbe.Track(kind: .audio, codec: "mp4a", isPlayable: true),
        ]
        let decision = router.decision(for: item("/movie.mov"), probe: MediaProbe(isPlayable: true, tracks: tracks))
        #expect(decision == .init(engine: .vlc, reason: .trackNotPlayable("hvc1")))
    }

    @Test func failedProbeFallsBackToVLC() {
        #expect(router.decision(for: item("/movie.mp4"), probe: nil) == .init(engine: .vlc, reason: .probeFailed))
        #expect(router.decision(for: item("/movie.mp4"), probe: probe([], playable: false)).engine == .vlc)
        // A container with no audio or video tracks isn't something AVPlayer should try.
        #expect(router.decision(for: item("/movie.mp4"), probe: probe([(.auxiliary, "tmcd")])).engine == .vlc)
    }

    @Test func unknownExtensionUsesProbe() {
        let unknown = item("/media/recording.xyz")
        #expect(router.quickDecision(for: unknown) == nil)
        #expect(router.decision(for: unknown, probe: probe([(.audio, "alac")])).engine == .avFoundation)
    }

    @Test func protectedContentStaysOnAVFoundation() {
        let protected = MediaProbe(isPlayable: true, hasProtectedContent: true, tracks: [])
        #expect(router.decision(for: item("/song.m4p"), probe: protected) == .init(engine: .avFoundation, reason: .protectedContent))
    }

    @Test func musicFormats() {
        #expect(router.decision(for: item("/a.flac"), probe: probe([(.audio, "flac")])).engine == .avFoundation)
        #expect(router.decision(for: item("/a.m4a"), probe: probe([(.audio, "alac")])).engine == .avFoundation)
        #expect(router.decision(for: item("/a.mp3"), probe: probe([(.audio, ".mp3")])).engine == .avFoundation)
        #expect(router.decision(for: item("/a.m4a"), probe: probe([(.audio, "opus")])).engine == .vlc)
    }

    @Test func reasonsExplainThemselves() {
        #expect(EngineRouter.Reason.unsupportedContainer("mkv").explanation == ".mkv files play with VLC")
        #expect(EngineRouter.Reason.unsupportedAudioCodec("dtsc").explanation.contains("dtsc"))
    }
}
