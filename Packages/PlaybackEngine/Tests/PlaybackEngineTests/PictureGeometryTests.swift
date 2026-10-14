#if os(macOS)
import AppKit
import Foundation
import PlaybackCore
import Testing
@testable import PlaybackEngine

/// Turning, mirroring and magnifying happen in the video view's container,
/// for both engines; 360° videos go to VLC and turn where you drag.
extension RealMediaTests {
    @MainActor
    @Suite("Turning, zoom and 360° video", .serialized)
    struct PictureGeometryTests {
        @Test func quarterTurnStandsTheViewOnEndAndTurnsItIntoPlace() throws {
            _ = NSApplication.shared
            let controller = PlaybackController()
            let window = NSWindow(contentRect: NSRect(x: 40, y: 40, width: 320, height: 180), styleMask: [.titled], backing: .buffered, defer: false)
            // Released by ARC, not by close() as well.
            window.isReleasedWhenClosed = false
            defer {
                window.orderOut(nil)
                window.contentView = nil
            }
            let container = VideoContainerView(frame: NSRect(x: 0, y: 0, width: 320, height: 180))
            container.controller = controller
            container.wantsLayer = true
            window.contentView = container
            controller.mountVideoView(in: container)
            #expect(controller.videoView.frame == container.bounds)

            controller.rotate()
            #expect(controller.videoView.frame == NSRect(x: 70, y: -70, width: 180, height: 320))
            let containerLayer = try #require(container.layer)
            // The container's sublayer transform turns the view into place
            // (CALayer.convert doesn't include sublayer transforms, so the
            // transform itself is checked; VideoPlacement's maths has its own tests).
            let turned = CATransform3DGetAffineTransform(containerLayer.sublayerTransform)
            Trace.write("geometry: quarter turn sublayer transform \(turned), anchor \(containerLayer.anchorPoint)")
            #expect(abs(turned.a) < 0.001 && abs(turned.d) < 0.001)
            #expect(abs(abs(turned.b) - 1) < 0.001 && abs(abs(turned.c) - 1) < 0.001)

            controller.setTransform(.identity)
            controller.setZoom(VideoZoom(scale: 2, centerX: 0.25, centerY: 0.5))
            let zoomed = CATransform3DGetAffineTransform(containerLayer.sublayerTransform)
            #expect(abs(zoomed.a - 2) < 0.001 && abs(zoomed.d - 2) < 0.001)

            controller.setZoom(.none)
            #expect(CATransform3DIsIdentity(containerLayer.sublayerTransform))
        }

        @Test func sphericalVideoPlaysWithVLCAndLooksAround() async throws {
            let name = "spherical"
            let watchdog = Watchdog(name: name, limit: 40)
            defer { watchdog.finish() }
            let flat = try await TestMovie.url(seconds: 6)
            let movie = try SphericalTestMovie.make(from: flat)
            defer { try? FileManager.default.removeItem(at: movie) }
            #expect(SphericalVideoDetector.projection(ofFileAt: movie) == .equirectangular)

            let controller = PlaybackController()
            let window = TestWindow(showing: controller.videoView)
            defer { window.close() }
            await controller.load(PlaybackItem(url: movie, kind: .video, title: "360"))
            let plays = await waitUntil(seconds: 10) { controller.state == .playing && controller.currentTime > 0.5 }
            Trace.write("\(name): \(plays ? "playing" : "DID NOT PLAY") with \(String(describing: controller.activeEngine)), reason \(String(describing: controller.routingReason)), projection \(controller.projection)")
            #expect(plays)
            #expect(controller.activeEngine == .vlc)
            #expect(controller.routingReason == .sphericalVideo)
            let projected = await waitUntil(seconds: 3) { controller.isSpherical }
            #expect(projected)

            // Dragging and pinching while it plays.
            for step in 1...20 {
                controller.setViewpoint(Viewpoint.straightAhead.dragged(byX: Double(step) * -20, y: Double(step) * 5, viewWidth: 320).zoomed(by: 1 + Double(step) / 40))
                try await Task.sleep(for: .milliseconds(30))
            }
            let before = controller.currentTime
            let moves = await waitUntil(seconds: 3) { controller.currentTime > before + 0.3 }
            Trace.write("\(name): after looking around, \(moves ? "still playing" : "STUCK"), view \(controller.viewpoint)")
            #expect(moves)
            // Turning and zooming leave a sphere alone.
            controller.rotate()
            #expect(controller.videoView.frame.size == controller.videoView.superview?.bounds.size)
            await controller.stop()
            #expect(controller.projection == .flat)
            #expect(controller.viewpoint == .straightAhead)
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

/// Copies the test movie with Google's Spherical Video V2 metadata added to
/// its video sample entry, as 360° cameras write it.
enum SphericalTestMovie {
    enum Failure: Error {
        case notFound(String)
    }

    static func make(from source: URL) throws -> URL {
        var data = try Data(contentsOf: source)
        let moov = try find("moov", in: data, range: 0..<data.count)
        // Inserting into the movie box moves nothing else only when it comes last.
        guard moov.upperBound == data.count else { throw Failure.notFound("moov at the end") }
        // moov ▸ trak ▸ mdia ▸ minf ▸ stbl ▸ stsd ▸ avc1, keeping each box on the way.
        var path: [Range<Int>] = [moov]
        var entry: Range<Int>?
        for trak in children(of: moov, in: data, headerExtra: 0) where type(at: trak.lowerBound, in: data) == "trak" {
            guard let mdia = children(of: trak, in: data, headerExtra: 0).first(where: { type(at: $0.lowerBound, in: data) == "mdia" }),
                  let minf = children(of: mdia, in: data, headerExtra: 0).first(where: { type(at: $0.lowerBound, in: data) == "minf" }),
                  let stbl = children(of: minf, in: data, headerExtra: 0).first(where: { type(at: $0.lowerBound, in: data) == "stbl" }),
                  let stsd = children(of: stbl, in: data, headerExtra: 0).first(where: { type(at: $0.lowerBound, in: data) == "stsd" }),
                  let avc1 = children(of: stsd, in: data, headerExtra: 8).first(where: { type(at: $0.lowerBound, in: data) == "avc1" })
            else { continue }
            path += [trak, mdia, minf, stbl, stsd]
            entry = avc1
            break
        }
        guard let entry else { throw Failure.notFound("avc1") }
        path.append(entry)

        let sv3d = box("sv3d", box("svhd", Data([0, 0, 0, 0, 0])) + box("proj", fullBox("prhd", Data(repeating: 0, count: 12)) + fullBox("equi", Data(repeating: 0, count: 16))))
        data.insert(contentsOf: sv3d, at: entry.upperBound)
        for box in path {
            let size = UInt32(box.count + sv3d.count)
            data.replaceSubrange(box.lowerBound..<box.lowerBound + 4, with: withUnsafeBytes(of: size.bigEndian, Array.init))
        }
        let url = FileManager.default.temporaryDirectory.appending(path: "coreplay-360-\(UUID().uuidString).mp4")
        try data.write(to: url)
        return url
    }

    private static func box(_ type: String, _ payload: Data) -> Data {
        var data = Data(withUnsafeBytes(of: UInt32(8 + payload.count).bigEndian, Array.init))
        data.append(Data(type.utf8))
        data.append(payload)
        return data
    }

    private static func fullBox(_ type: String, _ payload: Data) -> Data {
        box(type, Data([0, 0, 0, 0]) + payload)
    }

    private static func size(at offset: Int, in data: Data) -> Int {
        data[offset..<offset + 4].reduce(0) { $0 << 8 | Int($1) }
    }

    private static func type(at offset: Int, in data: Data) -> String {
        String(decoding: data[offset + 4..<offset + 8], as: UTF8.self)
    }

    private static func find(_ wanted: String, in data: Data, range: Range<Int>) throws -> Range<Int> {
        var offset = range.lowerBound
        while offset + 8 <= range.upperBound {
            var length = size(at: offset, in: data)
            if length == 1, offset + 16 <= range.upperBound {
                // A 64-bit size follows the type (AVAssetWriter's mdat).
                length = data[offset + 8..<offset + 16].reduce(0) { $0 << 8 | Int($1) }
            } else if length == 0 {
                length = range.upperBound - offset // runs to the end
            }
            guard length >= 8 else { break }
            if type(at: offset, in: data) == wanted {
                return offset..<offset + length
            }
            offset += length
        }
        throw Failure.notFound(wanted)
    }

    /// The boxes inside `parent`. `headerExtra` skips what comes before the
    /// first child: 8 for `stsd` (version, flags and entry count).
    private static func children(of parent: Range<Int>, in data: Data, headerExtra: Int) -> [Range<Int>] {
        var result: [Range<Int>] = []
        var offset = parent.lowerBound + 8 + headerExtra
        while offset + 8 <= parent.upperBound {
            let length = size(at: offset, in: data)
            guard length >= 8, offset + length <= parent.upperBound else { break }
            result.append(offset..<offset + length)
            offset += length
        }
        return result
    }
}
#endif

#if os(macOS)
/// Sound Check levels songs with their ReplayGain values, and Volume Boost
/// moves an item to VLC to go past 100%.
extension RealMediaTests {
    @MainActor
    @Suite("Sound Check and volume boost", .serialized)
    struct LoudnessPlaybackTests {
        @Test func soundCheckLevelsSongsAndBoostMovesToVLC() async throws {
            let name = "loudness"
            let watchdog = Watchdog(name: name, limit: 40)
            defer { watchdog.finish() }
            let url = ParitySamples.folder.appending(path: "tone-replaygain.flac")
            var item = PlaybackItem(url: url, kind: .audio, title: "ReplayGain Tone")
            item.replayGain = ReplayGainValues(trackGain: -6, trackPeak: 0.5, albumGain: -4, albumPeak: 0.6)

            let controller = PlaybackController()
            controller.setReplayGain(ReplayGainSettings(mode: .track))
            await controller.load(item)
            #expect(abs(controller.replayGainScale - 0.5012) < 0.001)
            controller.setReplayGain(ReplayGainSettings(mode: .album))
            #expect(abs(controller.replayGainScale - 0.6310) < 0.001)
            controller.setReplayGain(.off)
            #expect(controller.replayGainScale == 1)

            let plays = await waitUntil(seconds: 10) { controller.state == .playing }
            Trace.write("\(name): \(plays ? "playing" : "DID NOT PLAY") with \(String(describing: controller.activeEngine))")
            #expect(plays)
            await controller.setBoostedVolume(1.5)
            Trace.write("\(name): boosted to \(controller.volume) with \(String(describing: controller.activeEngine))")
            #expect(controller.activeEngine == .vlc)
            #expect(controller.volume == 1.5)
            // A film keeps its own sound.
            controller.setReplayGain(ReplayGainSettings(mode: .track))
            await controller.load(PlaybackItem(url: try await TestMovie.url(seconds: 6), kind: .video, title: "Film"))
            #expect(controller.replayGainScale == 1)
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
