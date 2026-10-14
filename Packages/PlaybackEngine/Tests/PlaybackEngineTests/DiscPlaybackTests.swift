#if os(macOS)
import Foundation
import PlaybackCore
import Testing
@testable import PlaybackEngine

/// The parity suite's DVD (a one-button menu whose button plays title 1;
/// title 1 runs on into title 2, which calls the menu again), opened as a
/// VIDEO_TS folder and as an image, through the controller as the app opens
/// it. Results join build/parity-report.md.
extension RealMediaTests {
    @MainActor
    @Suite("Discs: titles and menus", .serialized)
    struct DiscPlaybackTests {
        /// The official VLCKit is built without disc support: the player
        /// says so plainly instead of failing quietly.
        @Test(.enabled(if: !DiscLayout.canPlayDiscs))
        func discsSayTheyCantPlayYet() async throws {
            let controller = PlaybackController()
            for sample in ["dvd", "dvd.iso"] {
                await controller.load(PlaybackItem(url: ParitySamples.folder.appending(path: sample)))
                let message = controller.state.error?.message ?? "no error"
                Trace.write("disc-\(sample): \(message)")
                #expect(controller.currentItem?.disc == .dvd)
                #expect(controller.state.error?.code == .unsupportedFormat)
                ParityReport.add(
                    sample: sample,
                    covers: sample.hasSuffix(".iso") ? "Discs: DVD ISO image" : "Discs: VIDEO_TS folder with a menu",
                    engine: "vlc",
                    problems: ["not in VLCKit 4.0.0a25 (built with --disable-dvdnav --disable-dvdread)"],
                    details: "recognised as a DVD; the player explains it can't play discs"
                )
            }
            await controller.stop()
        }

        @Test(.enabled(if: DiscLayout.canPlayDiscs), arguments: ["dvd", "dvd.iso"])
        func dvdOpensAtItsMenuAndPlaysItsTitles(_ sample: String) async throws {
            let name = "disc-\(sample)"
            let watchdog = Watchdog(name: name, limit: 45)
            defer { watchdog.finish() }
            let controller = PlaybackController()
            let window = TestWindow(showing: controller.videoView)
            defer { window.close() }
            var problems: [String] = []

            await controller.load(PlaybackItem(url: ParitySamples.folder.appending(path: sample)))
            #expect(controller.currentItem?.disc == .dvd)
            #expect(controller.routingReason == .disc(.dvd))
            #expect(controller.activeEngine == .vlc)

            // VLC lists the menu and both titles, and starts in the menu.
            let listed = await waitUntil(seconds: 10) {
                controller.hasDiscMenu && MediaTitle.numbered(controller.titles).count == 2
            }
            Trace.write("\(name): titles \(Self.describe(controller.titles)), current \(String(describing: controller.currentTitleIndex)), state \(controller.state)")
            if !listed { problems.append("titles \(Self.describe(controller.titles)), expected a menu and 2 titles") }
            let inMenu = await waitUntil(seconds: 6) { controller.isShowingDiscMenu }
            if !inMenu { problems.append("didn't start in the menu (title \(String(describing: controller.currentTitleIndex)))") }

            // Select presses the menu's one button: the film starts.
            controller.navigateDisc(.activate)
            let playing = await waitUntil(seconds: 8) {
                controller.currentTitle.map { !$0.isMenu } == true && controller.state == .playing
            }
            Trace.write("\(name): after Select, title \(String(describing: controller.currentTitleIndex)) at \(controller.currentTime), state \(controller.state)")
            if !playing { problems.append("Select didn't start a title") }

            // Any title straight from the list.
            if let second = MediaTitle.numbered(controller.titles).last?.title {
                controller.selectTitle(second)
                let switched = await waitUntil(seconds: 6) { controller.currentTitleIndex == second.id }
                Trace.write("\(name): chose title \(second.id), now \(String(describing: controller.currentTitleIndex))")
                if !switched { problems.append("choosing title \(second.id) didn't play it") }
            }

            // And back to the menu.
            controller.navigateDisc(.menu)
            let backInMenu = await waitUntil(seconds: 8) { controller.isShowingDiscMenu }
            Trace.write("\(name): Menu, title \(String(describing: controller.currentTitleIndex))")
            if !backInMenu { problems.append("Menu didn't go back to the menu") }

            ParityReport.add(
                sample: sample,
                covers: sample.hasSuffix(".iso") ? "Discs: DVD ISO image" : "Discs: VIDEO_TS folder with a menu",
                engine: controller.activeEngine == .vlc ? "vlc" : "avFoundation (expected vlc)",
                problems: problems,
                details: "titles: \(Self.describe(controller.titles))"
            )
            #expect(problems.isEmpty, "\(sample): \(problems.joined(separator: "; "))")
            await controller.stop()
        }

        /// A disc played from where it was left skips its menu: the film
        /// starts at the time saved.
        @Test(.enabled(if: DiscLayout.canPlayDiscs))
        func aDiscResumesInItsFilm() async throws {
            let name = "disc-resume"
            let watchdog = Watchdog(name: name, limit: 30)
            defer { watchdog.finish() }
            let controller = PlaybackController()
            let window = TestWindow(showing: controller.videoView)
            defer { window.close() }

            var item = PlaybackItem(url: ParitySamples.folder.appending(path: "dvd", directoryHint: .isDirectory), kind: .video, title: "DVD")
            item.startPosition = 0.8
            await controller.load(item)
            let resumed = await waitUntil(seconds: 10) {
                !controller.isShowingDiscMenu && controller.isPlayingMainTitle && controller.currentTime >= 0.7
            }
            Trace.write("\(name): title \(String(describing: controller.currentTitleIndex)) of \(Self.describe(controller.titles)) at \(controller.currentTime)")
            #expect(resumed)
            await controller.stop()
        }

        private static func describe(_ titles: [MediaTitle]) -> String {
            titles.map { "\($0.id)\($0.isMenu ? " menu" : "") \(String(format: "%.1f", $0.duration))s" }.joined(separator: ", ")
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
