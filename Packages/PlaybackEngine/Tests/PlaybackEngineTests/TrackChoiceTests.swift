#if os(macOS)
import AppKit
import Foundation
import PlaybackCore
import Testing
@testable import PlaybackEngine

/// Videos start with the audio and subtitles you prefer, and play the way
/// you left them: tracks, timing and turning are remembered per file.
extension RealMediaTests {
    @MainActor
    @Suite("Starting tracks and remembered options", .serialized)
    struct TrackChoiceTests {
        @Test func preferredLanguagesPickTheTracks() async throws {
            let name = "track-preferences"
            let watchdog = Watchdog(name: name, limit: 40)
            defer { watchdog.finish() }
            let controller = PlaybackController()
            let window = TestWindow(showing: controller.videoView)
            defer { window.close() }

            controller.trackPreferences = TrackPreferences(audioLanguage: "fr", subtitles: .always, subtitleLanguage: "fr")
            await controller.load(PlaybackItem(url: ParitySamples.folder.appending(path: "two-audio-tracks.mkv"), kind: .video, title: "Two Audio Tracks"))
            let french = await waitUntil(seconds: 6) {
                MediaTrack.languagesMatch(controller.audioTracks.first(where: \.isSelected)?.languageCode, "fr")
            }
            Trace.write("\(name): audio \(controller.audioTracks.map { "\($0.languageCode ?? "?")\($0.isSelected ? "*" : "")" })")
            #expect(french)

            await controller.load(PlaybackItem(url: ParitySamples.folder.appending(path: "subtitles.mkv"), kind: .video, title: "Subtitles"))
            let frenchSubtitles = await waitUntil(seconds: 6) {
                MediaTrack.languagesMatch(controller.subtitleTracks.first(where: \.isSelected)?.languageCode, "fr")
            }
            Trace.write("\(name): subtitles \(controller.subtitleTracks.map { "\($0.languageCode ?? "?")\($0.isSelected ? "*" : "")" })")
            #expect(frenchSubtitles)
            await controller.stop()
        }

        @Test func optionsComeBackForTheSameFile() async throws {
            let name = "file-options"
            let watchdog = Watchdog(name: name, limit: 40)
            defer { watchdog.finish() }
            let controller = PlaybackController()
            let window = TestWindow(showing: controller.videoView)
            defer { window.close() }
            let url = ParitySamples.folder.appending(path: "subtitles.mkv")
            var remembered: [String: FileOptions] = [:]
            controller.rememberedOptions = { item in remembered[FileOptionsStore.key(for: item)] }
            controller.onOptionsChosen = { item, options in remembered[FileOptionsStore.key(for: item)] = options }

            // First time: choose English subtitles, a delay and a quarter turn.
            await controller.load(PlaybackItem(url: url, kind: .video, title: "Subtitles"))
            let listed = await waitUntil(seconds: 6) { controller.subtitleTracks.count >= 3 }
            #expect(listed)
            let english = try #require(controller.subtitleTracks.first { MediaTrack.languagesMatch($0.languageCode, "en") && !$0.isSelected } ?? controller.subtitleTracks.first { MediaTrack.languagesMatch($0.languageCode, "en") })
            controller.selectSubtitleTrack(english)
            await controller.setSubtitleDelay(0.4)
            controller.rotate()
            let saved = try #require(remembered[FileOptionsStore.key(for: PlaybackItem(url: url))])
            Trace.write("\(name): remembered \(saved)")
            #expect(MediaTrack.languagesMatch(saved.subtitleLanguage, "en"))
            #expect(saved.subtitleDelay == 0.4)
            #expect(saved.transform.rotation == .quarter)
            await controller.stop()
            #expect(controller.transform == .identity)

            // Next time, they come back.
            await controller.load(PlaybackItem(url: url, kind: .video, title: "Subtitles Again"))
            #expect(controller.subtitleDelay == 0.4)
            #expect(controller.transform.rotation == .quarter)
            let restored = await waitUntil(seconds: 6) {
                MediaTrack.languagesMatch(controller.subtitleTracks.first(where: \.isSelected)?.languageCode, "en")
            }
            Trace.write("\(name): restored subtitles \(controller.subtitleTracks.map { "\($0.languageCode ?? "?")\($0.isSelected ? "*" : "")" })")
            #expect(restored)
            await controller.stop()
        }

        /// Two subtitle tracks at once (VLC), then a new subtitle style:
        /// VLC restarts where it was, with both tracks still showing.
        @Test func twoSubtitlesSurviveANewStyle() async throws {
            let name = "dual-subtitles"
            let watchdog = Watchdog(name: name, limit: 40)
            defer { watchdog.finish() }
            let controller = PlaybackController()
            let window = TestWindow(showing: controller.videoView)
            defer { window.close() }

            await controller.load(PlaybackItem(url: ParitySamples.folder.appending(path: "subtitles.mkv"), kind: .video, title: "Subtitles"))
            let listed = await waitUntil(seconds: 6) { controller.subtitleTracks.count >= 3 && controller.state == .playing }
            #expect(listed)
            #expect(controller.activeEngine == .vlc)
            // Paused, so the three-second sample can't end under the test.
            controller.pause()
            let main = try #require(controller.subtitleTracks.first { MediaTrack.languagesMatch($0.languageCode, "en") })
            let second = try #require(controller.subtitleTracks.first { MediaTrack.languagesMatch($0.languageCode, "fr") })
            controller.selectSubtitleTrack(main)
            controller.selectSecondarySubtitleTrack(second)
            func showsBoth() -> Bool {
                controller.subtitleTracks.contains { $0.id == main.id && $0.isSelected && !$0.isSecondary }
                    && controller.subtitleTracks.contains { $0.id == second.id && $0.isSecondary }
            }
            let both = await waitUntil(seconds: 4) { showsBoth() }
            Trace.write("\(name): \(controller.subtitleTracks.map { "\($0.id)\($0.isSelected ? "*" : "")\($0.isSecondary ? "+" : "")" })")
            #expect(both)

            await controller.seek(to: 1.2)
            var style = controller.subtitleStyle
            style.isBold.toggle()
            await controller.setSubtitleStyle(style)
            let restored = await waitUntil(seconds: 8) {
                abs(controller.currentTime - 1.2) < 0.7 && showsBoth()
            }
            Trace.write("\(name): after a new style at \(controller.currentTime), \(controller.subtitleTracks.map { "\($0.id)\($0.isSelected ? "*" : "")\($0.isSecondary ? "+" : "")" })")
            #expect(restored)
            #expect(controller.subtitleStyle == style)
            await controller.stop()
        }

        private func waitUntil(seconds: Double, _ condition: () -> Bool) async -> Bool {
            let deadline = Date().addingTimeInterval(seconds)
            while Date() < deadline {
                if condition() {
                    return true
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
            return condition()
        }
    }
}
#endif
