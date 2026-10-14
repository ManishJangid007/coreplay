#if os(macOS)
import Foundation
import PlaybackCore
import Testing
@testable import PlaybackEngine

/// Playlist files from the parity suite, and cue sheet tracks played as
/// stretches of one recording.
extension RealMediaTests {
    @MainActor
    @Suite("Playlists and cue sheets", .serialized)
    struct PlaylistPlaybackTests {
        @Test func paritySuitePlaylistsListTheirFiles() throws {
            for (name, count) in [("playlist.m3u", 3), ("playlist.pls", 2), ("playlist.xspf", 3), ("album.cue", 3)] {
                let entries = try PlaylistFile.entries(at: ParitySamples.folder.appending(path: name))
                #expect(entries.count == count, "\(name)")
                for entry in entries {
                    #expect(FileManager.default.fileExists(atPath: entry.url.path(percentEncoded: false)), "\(name): \(entry.url.lastPathComponent)")
                }
            }
        }

        @Test func cueTracksPlayAsStretchesAndRunOnWithoutReopening() async throws {
            let name = "cue"
            let watchdog = Watchdog(name: name, limit: 40)
            defer { watchdog.finish() }
            let items = try PlaylistFile.entries(at: ParitySamples.folder.appending(path: "album.cue")).map(\.playbackItem)
            #expect(items.map(\.title) == ["First", "Second", "Third"])
            #expect(items[1].segment == PlaybackSegment(start: 3, end: 6))

            let controller = PlaybackController()
            var ends = 0
            controller.onChange = { change in
                if change == .endOfMedia { ends += 1 }
            }
            await controller.load(items[1])
            let plays = await waitUntil(seconds: 8) { controller.state == .playing && controller.currentTime > 0.2 }
            Trace.write("\(name): second track \(plays ? "playing" : "DID NOT PLAY"), time \(controller.currentTime) of \(String(describing: controller.duration))")
            #expect(plays)
            // Times count from the track's start, not the file's.
            #expect(controller.currentTime < 2.5)
            let duration = try #require(controller.duration)
            #expect(abs(duration - 3) < 0.2)

            let ended = await waitUntil(seconds: 6) { ends > 0 }
            Trace.write("\(name): end of the second track \(ended ? "reported" : "NOT REPORTED") at \(controller.currentTime)")
            #expect(ended)
            #expect(items[1].segment!.continues(into: items[2].segment!))
            controller.continueInto(items[2])
            #expect(controller.currentItem?.title == "Third")
            try await Task.sleep(for: .milliseconds(600))
            Trace.write("\(name): third track at \(controller.currentTime), state \(controller.state)")
            #expect(controller.state == .playing)
            #expect(controller.currentTime < 1.5)
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
