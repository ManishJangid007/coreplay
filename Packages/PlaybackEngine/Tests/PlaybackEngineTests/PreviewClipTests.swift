#if os(macOS)
import AppKit
import Foundation
import PlaybackCore
import Testing
@testable import PlaybackEngine

/// The hero carousel's clips play in a second controller next to the main
/// player. These replay what the carousel does to them, with VLC's real
/// video output: a clip stopping while the main player starts (Play on a
/// hero page), and a video view taken out of its window while VLC is still
/// drawing (a page changing, or the carousel going away).
///
/// A crash ends the test process; xcodebuild notes "Restarting after
/// unexpected exit" and macOS writes a crash report, which is the point.
extension RealMediaTests {
    @MainActor
    @Suite("Preview clips next to the player", .serialized)
    struct PreviewClipTests {
        @Test func clipStopsWhileThePlayerStarts() async throws {
            let name = "preview-then-player"
            let watchdog = Watchdog(name: name, limit: 40)
            defer { watchdog.finish() }
            let movie = try await TestMovie.url(seconds: 12)

            let preview = PlaybackController(purpose: .preview)
            preview.setFillMode(.fill)
            preview.setMuted(true)
            let previewWindow = TestWindow(showing: preview.videoView)
            defer { previewWindow.close() }
            Trace.write("\(name): clip load")
            await preview.load(PlaybackItem(url: movie, kind: .video, title: "Clip", startPosition: 2, enginePreference: .vlc, playsAudio: false))
            let clipPlays = await waitUntil(seconds: 10) { preview.state == .playing && preview.currentTime > 2.5 }
            Trace.write("\(name): clip \(clipPlays ? "playing" : "DID NOT PLAY"), state \(preview.state), time \(preview.currentTime)")
            #expect(clipPlays)
            #expect(preview.currentItem?.isPreview == true)

            let player = PlaybackController()
            let playerWindow = TestWindow(showing: player.videoView)
            defer { playerWindow.close() }
            Trace.write("\(name): player load while the clip stops")
            async let clipStopped: Void = preview.stop()
            await player.load(PlaybackItem(url: movie, kind: .video, title: "Movie", enginePreference: .vlc))
            await clipStopped
            Trace.write("\(name): clip stopped, state \(preview.state)")
            let playerPlays = await waitUntil(seconds: 10) { player.state == .playing && player.currentTime > 1 }
            Trace.write("\(name): player \(playerPlays ? "playing" : "DID NOT PLAY"), state \(player.state), time \(player.currentTime)")
            #expect(playerPlays)
            #expect(preview.state == .idle)
            await player.stop()
            Trace.write("\(name): done")
        }

        /// Only one VLC video output at a time: the player stops a clip before
        /// it opens anything, and a clip can't use VLC while the player has a video.
        @Test func clipsGiveWayToThePlayer() async throws {
            let name = "clips-give-way"
            let watchdog = Watchdog(name: name, limit: 60)
            defer { watchdog.finish() }
            let movie = try await TestMovie.url(seconds: 12)
            let clip = PlaybackItem(url: movie, kind: .video, title: "Clip", startPosition: 2, enginePreference: .vlc, playsAudio: false)

            let preview = PlaybackController(purpose: .preview)
            let previewWindow = TestWindow(showing: preview.videoView)
            defer { previewWindow.close() }
            await preview.load(clip)
            let clipPlays = await waitUntil(seconds: 10) { preview.state == .playing }
            Trace.write("\(name): clip \(clipPlays ? "playing" : "DID NOT PLAY"), state \(preview.state)")
            #expect(clipPlays)

            let player = PlaybackController()
            let playerWindow = TestWindow(showing: player.videoView)
            defer { playerWindow.close() }
            await player.load(PlaybackItem(url: movie, kind: .video, title: "Movie", enginePreference: .vlc))
            Trace.write("\(name): player opened; clip state \(preview.state), item \(preview.currentItem?.title ?? "none")")
            #expect(preview.state == .idle)
            #expect(preview.currentItem == nil)
            let playerPlays = await waitUntil(seconds: 10) { player.state == .playing && player.currentTime > 1 }
            #expect(playerPlays)

            await preview.load(clip)
            Trace.write("\(name): clip while the player has a video: state \(preview.state)")
            #expect(preview.state.error != nil)
            #expect(preview.activeEngine == nil)

            await player.stop()
            await preview.stop()
            await preview.load(clip)
            let playsAgain = await waitUntil(seconds: 10) { preview.state == .playing }
            Trace.write("\(name): clip after the player stopped: \(playsAgain ? "playing" : "DID NOT PLAY"), state \(preview.state)")
            #expect(playsAgain)
            await preview.stop()
            Trace.write("\(name): done")
        }

        @Test(arguments: [VideoSource.generatedH264, .mpeg2])
        func vlcKeepsGoingWhenItsViewLeavesTheWindow(_ source: VideoSource) async throws {
            let name = "view-leaves-window-\(source.rawValue)"
            let watchdog = Watchdog(name: name, limit: 40)
            defer { watchdog.finish() }
            let url = try await source.url()

            let controller = PlaybackController()
            let window = TestWindow(showing: controller.videoView)
            defer { window.close() }
            await controller.load(PlaybackItem(url: url, kind: .video, title: name, enginePreference: .vlc))
            let plays = await waitUntil(seconds: 10) { controller.state == .playing && controller.currentTime > 1 }
            Trace.write("\(name): \(plays ? "playing" : "DID NOT PLAY"), state \(controller.state)")
            #expect(plays)

            Trace.write("\(name): view out of its window")
            controller.videoView.removeFromSuperview()
            let before = controller.currentTime
            try? await Task.sleep(for: .seconds(2))
            Trace.write("\(name): after 2 s out of the window, state \(controller.state), time \(before) → \(controller.currentTime)")
            #expect(controller.state == .playing)

            Trace.write("\(name): view back in a window")
            let again = TestWindow(showing: controller.videoView)
            defer { again.close() }
            let resumed = controller.currentTime
            // The MPEG-2 sample is three seconds long, so it may simply reach its end.
            let moves = await waitUntil(seconds: 5) { controller.currentTime > resumed + 0.5 || controller.state == .ended }
            Trace.write("\(name): \(moves ? "still playing" : "STUCK"), state \(controller.state), time \(controller.currentTime)")
            #expect(moves)
            await controller.stop()
            Trace.write("\(name): done")
        }

        enum VideoSource: String, CaseIterable, Sendable {
            /// H.264 in MP4: VideoToolbox decodes it.
            case generatedH264 = "h264"
            /// MPEG-2: decoded in software, drawn through VLC's software path.
            case mpeg2 = "mpeg2"

            func url() async throws -> URL {
                switch self {
                case .generatedH264:
                    return try await TestMovie.url(seconds: 12)
                case .mpeg2:
                    return ParitySamples.folder.appending(path: "mpeg2-mp2.mpg")
                }
            }
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
