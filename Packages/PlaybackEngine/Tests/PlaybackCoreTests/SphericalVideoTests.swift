import Foundation
import Testing
@testable import PlaybackCore

/// 360° videos in MP4 go to VLC, which lets you look around them.
@Suite("360° video")
struct SphericalVideoTests {
    // MARK: Building boxes

    private func box(_ type: String, _ payload: Data = Data()) -> Data {
        var data = Data()
        let size = UInt32(8 + payload.count)
        data.append(contentsOf: withUnsafeBytes(of: size.bigEndian, Array.init))
        data.append(Data(type.utf8))
        data.append(payload)
        return data
    }

    /// A full box: version and flags before the payload.
    private func fullBox(_ type: String, _ payload: Data = Data()) -> Data {
        box(type, Data([0, 0, 0, 0]) + payload)
    }

    private func movie(videoSampleEntryExtras: Data) -> Data {
        let sampleEntry = box("avc1", Data(repeating: 0, count: 78) + videoSampleEntryExtras)
        let stsd = fullBox("stsd", Data([0, 0, 0, 1]) + sampleEntry)
        let trak = box("trak", box("mdia", box("minf", box("stbl", stsd))))
        return box("moov", fullBox("mvhd", Data(repeating: 0, count: 96)) + trak)
    }

    private func file(_ parts: [Data]) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "coreplay-360-\(UUID().uuidString).mp4")
        try parts.reduce(Data(), +).write(to: url)
        return url
    }

    private var ftyp: Data { box("ftyp", Data("isom".utf8) + Data([0, 0, 2, 0]) + Data("isommp41".utf8)) }

    // MARK: Tests

    @Test func sphericalV2IsFound() throws {
        let projection = box("proj", fullBox("prhd", Data(repeating: 0, count: 12)) + fullBox("equi", Data(repeating: 0, count: 16)))
        let sv3d = box("sv3d", box("svhd", Data([0, 0, 0, 0, 0])) + projection)
        let url = try file([ftyp, movie(videoSampleEntryExtras: sv3d), box("mdat", Data(repeating: 1, count: 64))])
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(SphericalVideoDetector.projection(ofFileAt: url) == .equirectangular)
    }

    @Test func cubeMapsAreTold() throws {
        let sv3d = box("sv3d", box("proj", fullBox("cbmp", Data(repeating: 0, count: 8))))
        let url = try file([ftyp, movie(videoSampleEntryExtras: sv3d)])
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(SphericalVideoDetector.projection(ofFileAt: url) == .cubeMap)
    }

    @Test func appleProjectedMediaIsFound() throws {
        let vexu = box("vexu", box("proj", fullBox("prji", Data("equi".utf8))))
        let url = try file([ftyp, movie(videoSampleEntryExtras: vexu)])
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(SphericalVideoDetector.projection(ofFileAt: url) == .equirectangular)

        // A half-sphere (180°) isn't treated as 360°.
        let half = box("vexu", box("proj", fullBox("prji", Data("hequ".utf8))))
        let halfURL = try file([ftyp, movie(videoSampleEntryExtras: half)])
        defer { try? FileManager.default.removeItem(at: halfURL) }
        #expect(SphericalVideoDetector.projection(ofFileAt: halfURL) == .flat)
    }

    @Test func sphericalV1IsFound() throws {
        let xml = Data("<rdf:SphericalVideo><GSpherical:Spherical>true</GSpherical:Spherical><GSpherical:ProjectionType>equirectangular</GSpherical:ProjectionType></rdf:SphericalVideo>".utf8)
        let uuid = box("uuid", Data(SphericalVideoDetector.sphericalV1UUID) + xml)
        let moov = box("moov", fullBox("mvhd", Data(repeating: 0, count: 96)) + box("trak", uuid))
        let url = try file([ftyp, moov])
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(SphericalVideoDetector.projection(ofFileAt: url) == .equirectangular)
    }

    @Test func movieBoxAfterALargeMediaBoxIsFound() throws {
        // A 64-bit media box first, as streaming-unfriendly files have.
        var mdat = Data()
        let payload = Data(repeating: 2, count: 1_000)
        mdat.append(contentsOf: withUnsafeBytes(of: UInt32(1).bigEndian, Array.init))
        mdat.append(Data("mdat".utf8))
        mdat.append(contentsOf: withUnsafeBytes(of: UInt64(16 + payload.count).bigEndian, Array.init))
        mdat.append(payload)
        let sv3d = box("sv3d", box("proj", fullBox("equi", Data(repeating: 0, count: 16))))
        let url = try file([ftyp, mdat, movie(videoSampleEntryExtras: sv3d)])
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(SphericalVideoDetector.projection(ofFileAt: url) == .equirectangular)
    }

    @Test func ordinaryVideosAreFlat() throws {
        let url = try file([ftyp, movie(videoSampleEntryExtras: box("pasp", Data([0, 0, 0, 1, 0, 0, 0, 1])))])
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(SphericalVideoDetector.projection(ofFileAt: url) == .flat)
        // Not a movie file at all, or not there.
        let text = try file([Data("hello".utf8)])
        defer { try? FileManager.default.removeItem(at: text) }
        #expect(SphericalVideoDetector.projection(ofFileAt: text) == .flat)
        #expect(SphericalVideoDetector.projection(ofFileAt: URL(filePath: "/nonexistent/clip.mp4")) == .flat)
    }

    @Test func sphericalVideoRoutesToVLC() {
        let router = EngineRouter()
        let item = PlaybackItem(url: URL(filePath: "/Movies/Alps 360.mp4"), kind: .video, title: "Alps")
        let tracks = [
            MediaProbe.Track(kind: .video, codec: FourCC("avc1"), isPlayable: true),
            MediaProbe.Track(kind: .audio, codec: FourCC("mp4a"), isPlayable: true),
        ]
        let flat = router.decision(for: item, probe: MediaProbe(isPlayable: true, tracks: tracks))
        #expect(flat.engine == .avFoundation)
        let spherical = router.decision(for: item, probe: MediaProbe(isPlayable: true, tracks: tracks, projection: .equirectangular))
        #expect(spherical == EngineRouter.Decision(engine: .vlc, reason: .sphericalVideo))
        #expect(EngineRouter.Reason.sphericalVideo.explanation.contains("360"))
    }
}
