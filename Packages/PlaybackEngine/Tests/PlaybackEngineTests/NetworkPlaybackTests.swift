#if os(macOS)
import Foundation
import PlaybackCore
import Testing
@testable import PlaybackEngine

/// Shares and streams through the app's own browser and controller, against
/// servers running in the test process (TestServers.swift): an FTP server
/// that wants a login, and an HTTP server with byte ranges. Discovery and
/// casting modules are checked for, and what they find is written to the trace.
extension RealMediaTests {
    @MainActor
    @Suite("Network shares and streams", .serialized)
    struct NetworkPlaybackTests {
        static let login = NetworkCredential(user: "coreplay", password: "s3cret pass")

        @Test func ftpFolderListsWithASavedLogin() async throws {
            let server = try #require(TestFTPServer(root: ParitySamples.folder, user: Self.login.user, password: Self.login.password))
            defer { server.stop() }
            let entries = try await NetworkBrowser.shared.contents(of: server.url, credential: Self.login, asksForLogin: false)
            Trace.write("ftp-list: \(entries.count) entries: \(entries.prefix(6).map(\.name)); sidecars \(entries.filter { $0.name.hasPrefix("sidecar") }.map { "\($0.name) \($0.kind)" }); commands \(server.log.prefix(14))")
            let sample = try #require(entries.first { $0.name == "h264-aac.mp4" })
            #expect(sample.kind == .video)
            let size = try FileManager.default.attributesOfItem(atPath: ParitySamples.folder.appending(path: "h264-aac.mp4").path)[.size] as? NSNumber
            #expect(sample.size == size?.int64Value)
            #expect(sample.url.scheme == "ftp")
            #expect(sample.url.user == nil)
            #expect(entries.first { $0.name == "dvd" }?.isFolder == true)
            #expect(entries.first?.isFolder == true, "folders come first")
            #expect(entries.contains { $0.name == "tone.opus" && $0.kind == .audio })
            #expect(entries.contains { $0.kind == .subtitle })

            // A folder inside.
            let dvd = try #require(entries.first { $0.name == "dvd" })
            let inside = try await NetworkBrowser.shared.contents(of: dvd.url, credential: Self.login, asksForLogin: false)
            Trace.write("ftp-list: dvd holds \(inside.map(\.name))")
            #expect(inside.contains { $0.name == "VIDEO_TS" && $0.isFolder })
            ParityReport.add(sample: "ftp://127.0.0.1", covers: "Network shares: FTP folders with a saved login", engine: "vlc", problems: [], details: "\(entries.count) items, sizes and folders read")
        }

        @Test func ftpAsksForALoginWhenNoneIsSaved() async throws {
            let server = try #require(TestFTPServer(root: ParitySamples.folder, user: Self.login.user, password: Self.login.password))
            defer { server.stop() }
            let prompt = NetworkLoginPrompt.shared
            let recorder = Recorder<NetworkLoginPrompt.Request>()
            prompt.automaticAnswer = { request in
                recorder.items.append(request)
                return Self.login
            }
            defer { prompt.automaticAnswer = nil }
            let entries = try await NetworkBrowser.shared.contents(of: server.url)
            let asked = recorder.items
            Trace.write("ftp-login: asked \(asked.map { "\($0.title) / \($0.message) / \($0.address?.absoluteString ?? "-")" }); \(entries.count) entries")
            #expect(asked.count >= 1)
            #expect(asked.first?.address?.host == "127.0.0.1")
            #expect(entries.contains { $0.name == "h264-aac.mp4" })

            // Without asking, a wrong password fails plainly. (Another server:
            // VLC keeps logins that worked in memory, per server, until it quits.)
            let other = try #require(TestFTPServer(root: ParitySamples.folder, user: Self.login.user, password: Self.login.password))
            defer { other.stop() }
            await #expect(throws: NetworkBrowser.BrowseError.self) {
                _ = try await NetworkBrowser.shared.contents(of: other.url, credential: NetworkCredential(user: "coreplay", password: "wrong"), asksForLogin: false)
            }
            ParityReport.add(sample: "ftp://127.0.0.1", covers: "Network shares: VLC asks for a login (dialog provider)", engine: "vlc", problems: asked.isEmpty ? ["no login asked for"] : [], details: "asked: \(asked.first?.title ?? "nothing")")
        }

        @Test func playsAFileFromFTP() async throws {
            let server = try #require(TestFTPServer(root: ParitySamples.folder, user: Self.login.user, password: Self.login.password))
            defer { server.stop() }
            let watchdog = Watchdog(name: "ftp-play", limit: 40)
            defer { watchdog.finish() }
            let controller = PlaybackController()
            let window = TestWindow(showing: controller.videoView)
            defer { window.close() }
            let looked = Recorder<URL>()
            controller.networkCredentials = { url in
                looked.items.append(url)
                return Self.login
            }
            let url = server.url.appending(path: "h264-aac.mp4")
            await controller.load(PlaybackItem(url: url))
            let playing = await waitUntil(seconds: 10) { controller.state == .playing && controller.currentTime > 0.3 }
            Trace.write("ftp-play: \(controller.state) at \(controller.currentTime), duration \(String(describing: controller.duration)), engine \(String(describing: controller.activeEngine)), reason \(String(describing: controller.routingReason))")
            #expect(controller.activeEngine == .vlc)
            #expect(looked.items.contains(url))
            #expect(playing)
            #expect(abs((controller.duration ?? 0) - 3) < 0.5)
            await controller.stop()
            ParityReport.add(sample: "h264-aac.mp4 over FTP", covers: "Network shares: play a file from a share", engine: "vlc", problems: playing ? [] : ["didn't play (\(controller.state))"], details: "login handed to VLC as options")
        }

        @Test func playsHTTPOnBothEngines() async throws {
            let server = try #require(TestHTTPServer(root: ParitySamples.folder))
            defer { server.stop() }
            let watchdog = Watchdog(name: "http-play", limit: 50)
            defer { watchdog.finish() }
            let controller = PlaybackController()
            let window = TestWindow(showing: controller.videoView)
            defer { window.close() }

            for (name, engine) in [("h264-aac.mp4", EngineKind.avFoundation), ("vp9-opus.webm", EngineKind.vlc)] {
                await controller.load(PlaybackItem(url: server.url(for: name)))
                let playing = await waitUntil(seconds: 10) { controller.state == .playing && controller.currentTime > 0.3 }
                Trace.write("http-play \(name): \(controller.state) at \(controller.currentTime) on \(String(describing: controller.activeEngine)); requests \(server.log.suffix(4))")
                #expect(controller.activeEngine == engine, "\(name)")
                #expect(playing, "\(name)")
                ParityReport.add(sample: "\(name) over HTTP", covers: "Network streams: HTTP progressive", engine: engine == .vlc ? "vlc" : "avFoundation", problems: playing ? [] : ["didn't play (\(controller.state))"], details: "byte ranges from a local server")
                await controller.stop()
            }
        }

        @Test func discoveryAndCastingModulesArePresent() async throws {
            let services = NetworkDiscovery.availableServices
            let renderers = CastingCenter.discoveryServices
            Trace.write("discovery: LAN services \(services); renderer services \(renderers)")
            #expect(services.contains("upnp"))
            #expect(services.contains { $0.lowercased() == "bonjour" } || services.contains("dsm"))
            #expect(!renderers.isEmpty)

            NetworkDiscovery.shared.start()
            CastingCenter.shared.startSearching()
            try await Task.sleep(for: .seconds(3))
            Trace.write("discovery: running \(NetworkDiscovery.shared.runningServices), found \(NetworkDiscovery.shared.servers.map { "\($0.name) \($0.url.absoluteString)" }); cast targets \(CastingCenter.shared.targets.map(\.name))")
            #expect(!NetworkDiscovery.shared.runningServices.isEmpty)
            NetworkDiscovery.shared.stop()
            CastingCenter.shared.stopSearching()
            ParityReport.add(sample: "local network", covers: "Network shares: discovery; Casting: renderer discovery", engine: "vlc", problems: [], details: "modules: \(services.joined(separator: ", ")); renderers: \(renderers.joined(separator: ", "))")
        }

        /// Collects what a callback was given.
        @MainActor
        final class Recorder<Item> {
            var items: [Item] = []
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
