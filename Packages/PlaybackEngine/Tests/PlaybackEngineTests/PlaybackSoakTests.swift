#if os(macOS)
import Foundation
import PlaybackCore
import Testing
@testable import PlaybackEngine

/// Soak: opening one thing after another, quickly, across both engines
/// and with seeks in between, must leave the player healthy: no crash, no
/// hang (the watchdog), no stuck item, and the next file plays normally.
extension RealMediaTests {
    @MainActor
    @Suite("Soak", .serialized)
    struct PlaybackSoakTests {
        @Test func rapidSwitchingLeavesThePlayerHealthy() async throws {
            let watchdog = Watchdog(name: "soak", limit: 150)
            defer { watchdog.finish() }
            let controller = PlaybackController()
            let window = TestWindow(showing: controller.videoView)
            defer { window.close() }
            let samples = [
                "h264-aac.mp4", "vp9-opus.webm", "tone-alac.m4a", "subtitles.mkv", "hevc-aac.mp4",
                "tone.opus", "xvid-mp3.avi", "tone-replaygain.flac", "mpeg2-ac3.ts", "prores-pcm.mov",
            ]
            var failures: [String] = []
            var loads = 0
            let started = Date()
            for round in 0..<5 {
                for (index, name) in samples.enumerated() {
                    await controller.load(PlaybackItem(url: ParitySamples.folder.appending(path: name)))
                    loads += 1
                    try? await Task.sleep(for: .milliseconds(120 + ((round * 7 + index * 13) % 5) * 90))
                    if (round + index).isMultiple(of: 3) {
                        await controller.seek(to: 1.2)
                    }
                    if case .failed(let error) = controller.state {
                        failures.append("\(name): \(error.message)")
                    }
                }
            }
            await controller.stop()
            #expect(controller.currentItem == nil)

            await controller.load(PlaybackItem(url: ParitySamples.folder.appending(path: "h264-aac.mp4")))
            let healthy = await waitUntil(seconds: 8) { controller.state == .playing && controller.currentTime > 0.3 }
            Trace.write("soak: \(loads) loads in \(String(format: "%.1f", Date().timeIntervalSince(started))) s, failures \(failures), then \(controller.state) at \(controller.currentTime)")
            #expect(failures.isEmpty, "\(failures)")
            #expect(healthy)
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
