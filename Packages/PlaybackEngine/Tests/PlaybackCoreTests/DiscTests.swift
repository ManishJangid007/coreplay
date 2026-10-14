import Foundation
import Testing
@testable import PlaybackCore

/// The parity suite's DVD (Tests/ParitySamples/dvd and dvd.iso, made by
/// dvdauthor and genisoimage): two 2-second NTSC titles with English DVD
/// subtitles, and a one-button menu.
enum DiscSamples {
    static var folder: URL {
        // Packages/PlaybackEngine/Tests/PlaybackCoreTests/DiscTests.swift → the repository.
        URL(fileURLWithPath: #filePath)
            .resolvingSymlinksInPath()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Tests/ParitySamples", directoryHint: .isDirectory)
    }

    static var dvdFolder: URL { folder.appending(path: "dvd", directoryHint: .isDirectory) }
    static var dvdImage: URL { folder.appending(path: "dvd.iso") }

    /// A scratch folder, removed by the caller.
    static func temporaryFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "coreplay-disc-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// A small ISO 9660 image whose root holds `folders`.
    static func iso9660Image(folders: [String], label: String = "TEST_DISC") -> Data {
        var image = Data(count: 2_048 * 24)
        func put(_ bytes: [UInt8], at offset: Int) {
            image.replaceSubrange(offset..<(offset + bytes.count), with: bytes)
        }
        func record(name: [UInt8], sector: Int, size: Int) -> [UInt8] {
            var bytes: [UInt8] = [0, 0]
            bytes += le32(sector) + be32(sector) + le32(size) + be32(size)
            bytes += [UInt8](repeating: 0, count: 7) + [2, 0, 0] + [1, 0, 0, 1] + [UInt8(name.count)] + name
            if bytes.count % 2 == 1 { bytes.append(0) }
            bytes[0] = UInt8(bytes.count)
            return bytes
        }
        // Primary volume descriptor, then the terminator.
        put([1] + Array("CD001".utf8) + [1], at: 16 * 2_048)
        put(Array(label.padding(toLength: 32, withPad: " ", startingAt: 0).utf8), at: 16 * 2_048 + 40)
        put(record(name: [0], sector: 20, size: 2_048), at: 16 * 2_048 + 156)
        put([255] + Array("CD001".utf8) + [1], at: 17 * 2_048)
        // The root folder at sector 20.
        var root = record(name: [0], sector: 20, size: 2_048) + record(name: [1], sector: 20, size: 2_048)
        for (index, name) in folders.enumerated() {
            root += record(name: Array(name.utf8), sector: 21 + index, size: 2_048)
        }
        put(root, at: 20 * 2_048)
        return image
    }

    static func le32(_ value: Int) -> [UInt8] {
        [UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF), UInt8((value >> 16) & 0xFF), UInt8((value >> 24) & 0xFF)]
    }

    static func be32(_ value: Int) -> [UInt8] {
        le32(value).reversed()
    }
}

@Suite("Finding discs")
struct DiscLayoutTests {
    @Test func dvdFolderItsVideoTSAndItsIFOAreTheSameDisc() throws {
        let root = DiscSamples.dvdFolder
        for url in [root, root.appending(path: "VIDEO_TS", directoryHint: .isDirectory), root.appending(path: "VIDEO_TS/VIDEO_TS.IFO")] {
            let disc = try #require(DiscLayout.disc(at: url), "\(url.path)")
            #expect(disc.kind == .dvd)
            #expect(!disc.isImage)
            #expect(disc.root.standardizedFileURL.path == root.standardizedFileURL.path)
            #expect(disc.playbackURL.lastPathComponent == "VIDEO_TS")
            #expect(disc.displayName == "dvd")
        }
        #expect(DiscLayout.kind(ofFolderAt: root) == .dvd)
        // A VOB played by itself stays a file, as in VLC.
        #expect(DiscLayout.disc(at: root.appending(path: "VIDEO_TS/VTS_01_1.VOB")) == nil)
    }

    @Test func dvdImage() throws {
        let disc = try #require(DiscLayout.disc(at: DiscSamples.dvdImage))
        #expect(disc.kind == .dvd)
        #expect(disc.isImage)
        #expect(disc.volumeName == "PARITY_DVD")
        #expect(disc.displayName == "dvd")
        #expect(disc.playbackURL == disc.root)
    }

    @Test func blurayFolderOnACaseSensitiveDisk() throws {
        let root = try DiscSamples.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let movie = root.appending(path: "Heat (1995)", directoryHint: .isDirectory)
        let bdmv = movie.appending(path: "bdmv", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: bdmv.appending(path: "PLAYLIST"), withIntermediateDirectories: true)
        try Data("INDX0200".utf8).write(to: bdmv.appending(path: "index.bdmv"))

        let disc = try #require(DiscLayout.disc(at: movie))
        #expect(disc.kind == .bluray)
        #expect(disc.displayName == "Heat (1995)")
        #expect(disc.playbackURL == disc.root)
        #expect(DiscLayout.disc(at: bdmv)?.root.lastPathComponent == "Heat (1995)")
        #expect(DiscLayout.disc(at: root) == nil)
        #expect(DiscLayout.kind(ofFolderAt: root) == nil)
    }

    @Test func imagesOfOtherDiscsAndOtherFilesAreNotDiscs() throws {
        let root = try DiscSamples.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let data = root.appending(path: "Installer.iso")
        try DiscSamples.iso9660Image(folders: ["DATA", "TOOLS"]).write(to: data)
        #expect(DiscLayout.disc(at: data) == nil)

        let random = root.appending(path: "Random.img")
        try Data((0..<100_000).map { UInt8(truncatingIfNeeded: $0 &* 31) }).write(to: random)
        #expect(DiscLayout.disc(at: random) == nil)

        #expect(DiscLayout.disc(at: root.appending(path: "Missing.iso")) == nil)
        #expect(DiscLayout.disc(at: DiscSamples.folder.appending(path: "h264-aac.mp4")) == nil)
        #expect(!DiscLayout.mightBeDisc(DiscSamples.folder.appending(path: "h264-aac.mp4")))
        #expect(DiscLayout.mightBeDisc(DiscSamples.dvdFolder))
        #expect(DiscLayout.mightBeDisc(DiscSamples.dvdImage))
        #expect(!DiscLayout.mightBeDisc(URL(string: "https://example.com/movie.iso")!))
        #expect(DiscLayout.disc(at: URL(string: "https://example.com/movie.iso")!) == nil)
    }

    @Test func iso9660ImagesAreRecognisedByTheirRootFolder() throws {
        let root = try DiscSamples.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let dvd = root.appending(path: "Movie.iso")
        try DiscSamples.iso9660Image(folders: ["AUDIO_TS", "VIDEO_TS"], label: "MOVIE_DISC_1").write(to: dvd)
        let disc = try #require(DiscLayout.disc(at: dvd))
        #expect(disc.kind == .dvd)
        #expect(disc.volumeName == "MOVIE_DISC_1")

        let bluray = root.appending(path: "Film.img")
        try DiscSamples.iso9660Image(folders: ["BDMV", "CERTIFICATE"]).write(to: bluray)
        #expect(DiscLayout.disc(at: bluray)?.kind == .bluray)
    }

    @Test func udfOnlyBlurayImage() throws {
        let root = try DiscSamples.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        var image = Data(count: 600_000)
        for (sector, identifier) in [(16, "BEA01"), (17, "NSR03"), (18, "TEA01")] {
            image.replaceSubrange((sector * 2_048)..<(sector * 2_048 + 7), with: [0] + Array(identifier.utf8) + [1])
        }
        // A file identifier in UTF-16 ("BDMV" with compression ID 16).
        let name: [UInt8] = [16] + Array("BDMV".utf8).flatMap { [0, $0] }
        image.replaceSubrange(500_000..<(500_000 + name.count), with: name)
        let url = root.appending(path: "Film.iso")
        try image.write(to: url)
        #expect(DiscLayout.disc(at: url)?.kind == .bluray)
    }

    @Test func itemsBecomeTheirDisc() throws {
        let videoTS = DiscSamples.dvdFolder.appending(path: "VIDEO_TS", directoryHint: .isDirectory)
        let disc = try #require(DiscLayout.disc(at: videoTS))
        let opened = PlaybackItem(url: videoTS, startPosition: 30).playing(disc)
        #expect(opened.title == "dvd")
        #expect(opened.disc == .dvd)
        #expect(opened.kind == .video)
        #expect(opened.url == disc.playbackURL)
        #expect(opened.startPosition == 30)

        // The library's own title stays.
        let fromLibrary = PlaybackItem(url: DiscSamples.dvdFolder, title: "Heat", libraryID: UUID()).playing(disc)
        #expect(fromLibrary.title == "Heat")
        #expect(fromLibrary.disc == .dvd)
    }

    @Test func readableVolumeNames() {
        #expect(Disc.readableVolumeName("HEAT_DISC_1") == "Heat Disc 1")
        let volume = Disc(kind: .dvd, root: URL(filePath: "/"), isImage: false, volumeName: "THE_THING")
        #expect(volume.displayName == "The Thing")
    }
}

@Suite("DVD and Blu-ray structure")
struct DiscInfoTests {
    @Test func dvdFolder() throws {
        let disc = try #require(DiscLayout.disc(at: DiscSamples.dvdFolder))
        let info = try #require(DVDVideoInfo.read(disc))
        try Self.checkParityDVD(info)
    }

    @Test func dvdImage() throws {
        let disc = try #require(DiscLayout.disc(at: DiscSamples.dvdImage))
        let info = try #require(DVDVideoInfo.read(disc))
        try Self.checkParityDVD(info)
    }

    static func checkParityDVD(_ info: DVDVideoInfo) throws {
        #expect(info.titles.count == 2)
        #expect(info.titles.map(\.number) == [1, 2])
        #expect(info.titles.allSatisfy { $0.titleSet == 1 && $0.chapters == 1 && $0.angles == 1 })
        for title in info.titles {
            #expect(abs(title.duration - 2) < 0.1, "title \(title.number): \(title.duration)")
        }
        #expect(info.hasMenu)
        let video = try #require(info.video)
        #expect(video.codec == "MPEG-2")
        #expect(video.width == 720 && video.height == 480)
        #expect(abs(video.frameRate - 29.97) < 0.01)
        #expect(info.audio.count == 1)
        #expect(info.audio.first?.codec == "AC-3")
        #expect(info.subtitles.map(\.language) == ["en"])
    }

    @Test func playbackTimes() {
        // 1:52:04 and 12 frames at 29.97 (0xD2: rate bits 11, frames 12), then 0:42:10 at 25.
        let bytes = BigEndianBytes(Data([0x01, 0x52, 0x04, 0xD2, 0x00, 0x42, 0x10, 0x40] as [UInt8]))
        #expect(abs(DVDVideoInfo.playbackTime(bytes, at: 0) - (6_724 + 12 / 29.97)) < 0.001)
        #expect(DVDVideoInfo.playbackTime(bytes, at: 4) == 2_530)
        #expect(DVDVideoInfo.playbackTime(bytes, at: 6) == 0) // runs off the end
    }

    @Test func notADVD() {
        #expect(DVDVideoInfo.read { _ in Data("not an IFO".utf8) } == nil)
        #expect(DVDVideoInfo.read { _ in nil } == nil)
    }

    /// An MPLS file as Blu-ray authoring tools write it: two play items,
    /// four chapter marks, and an H.264 1080p track, TrueHD 5.1 English and
    /// AC-3 French audio, English and French subtitles.
    static func mpls(firstItemSeconds: Int = 3_600, secondItemSeconds: Int = 1_200) -> Data {
        func u16(_ value: Int) -> [UInt8] { [UInt8(value >> 8), UInt8(value & 0xFF)] }
        func u32(_ value: Int) -> [UInt8] { u16(value >> 16) + u16(value & 0xFFFF) }
        func stream(entry: [UInt8], attributes: [UInt8]) -> [UInt8] {
            [UInt8(entry.count)] + entry + [UInt8(attributes.count)] + attributes
        }
        let entry: [UInt8] = [1, 0x10, 0x11, 0, 0, 0, 0, 0, 0] // type 1, PID 0x1011
        var streams: [UInt8] = []
        streams += stream(entry: entry, attributes: [0x1B, 0x61, 0, 0, 0]) // H.264, 1080p, 23.976
        streams += stream(entry: entry, attributes: [0x83, 0x61] + Array("eng".utf8)) // TrueHD, multi-channel
        streams += stream(entry: entry, attributes: [0x81, 0x31] + Array("fra".utf8)) // AC-3, stereo
        streams += stream(entry: entry, attributes: [0x90] + Array("eng".utf8) + [0])
        streams += stream(entry: entry, attributes: [0x90] + Array("fre".utf8) + [0])
        let table = u16(14 + streams.count) + [0, 0, 1, 2, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0] + streams

        func playItem(clip: String, in inTime: Int, out outTime: Int, withStreams: Bool) -> [UInt8] {
            var body = Array(clip.utf8) + Array("M2TS".utf8) + [0x00, 0x01] + [0]
            body += u32(inTime) + u32(outTime) + [UInt8](repeating: 0, count: 8) + [0, 0, 0, 0]
            body += withStreams ? table : u16(14) + [UInt8](repeating: 0, count: 14)
            return u16(body.count) + body
        }
        let items = playItem(clip: "00001", in: 900_000, out: 900_000 + 45_000 * firstItemSeconds, withStreams: true)
            + playItem(clip: "00002", in: 0, out: 45_000 * secondItemSeconds, withStreams: false)
        let playList = u32(6 + items.count) + [0, 0] + u16(2) + u16(0) + items
        var marks: [UInt8] = []
        for (index, type) in [1, 1, 2, 1, 1].enumerated() {
            marks += [0, UInt8(type)] + u16(0) + u32(index * 45_000 * 600) + u16(0xFFFF) + u32(0)
        }
        let markTable = u32(2 + marks.count) + u16(5) + marks

        let header = 40
        let listStart = header
        let marksStart = listStart + playList.count
        var file = Array("MPLS0200".utf8) + u32(listStart) + u32(marksStart) + u32(0)
        file += [UInt8](repeating: 0, count: header - file.count)
        return Data(file + playList + markTable)
    }

    @Test func blurayPlaylist() throws {
        let playlist = try #require(BlurayInfo.playlist(Self.mpls(), name: "00800"))
        #expect(playlist.duration == 3_600 + 1_200)
        #expect(playlist.chapters == 4)
        let video = try #require(playlist.video)
        #expect(video.codec == "H.264")
        #expect(video.width == 1_920 && video.height == 1_080)
        #expect(abs((video.frameRate ?? 0) - 23.976) < 0.001)
        #expect(playlist.audio.map(\.codec) == ["Dolby TrueHD", "AC-3"])
        #expect(playlist.audio.map(\.channels) == [6, 2])
        #expect(playlist.audio.map(\.language) == ["eng", "fra"])
        #expect(playlist.subtitles == ["eng", "fre"])
        #expect(BlurayInfo.playlist(Data("MOBJ0200".utf8), name: "x") == nil)
    }

    @Test func blurayFolderPicksTheLongestPlaylist() throws {
        let root = try DiscSamples.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let playlists = root.appending(path: "BDMV/PLAYLIST", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: playlists, withIntermediateDirectories: true)
        try Data("INDX0200".utf8).write(to: root.appending(path: "BDMV/index.bdmv"))
        try Self.mpls().write(to: playlists.appending(path: "00800.mpls"))
        // A trailer, and a playlist cut short.
        try Self.mpls(firstItemSeconds: 90, secondItemSeconds: 30).write(to: playlists.appending(path: "00001.mpls"))
        try Data(Self.mpls().prefix(40)).write(to: playlists.appending(path: "00002.mpls"))

        let disc = try #require(DiscLayout.disc(at: root))
        let info = try #require(BlurayInfo.read(disc))
        #expect(info.playlists.map(\.name) == ["00001", "00800"])
        #expect(info.mainPlaylist?.name == "00800")
        #expect(info.mainPlaylist?.duration == 4_800)
    }
}

@Suite("Titles")
struct MediaTitleTests {
    let titles = [
        MediaTitle(id: 0, name: "DVD Menu", isMenu: true, isInteractive: true),
        MediaTitle(id: 1, duration: 6_724, chapterCount: 24),
        MediaTitle(id: 2, duration: 754, chapterCount: 1),
        MediaTitle(id: 3, name: "Trailer", duration: 132),
    ]

    @Test func namesAndDetails() {
        let numbered = MediaTitle.numbered(titles)
        #expect(numbered.map(\.number) == [1, 2, 3])
        #expect(numbered.map { $0.title.displayName(number: $0.number) } == ["Title 1", "Title 2", "Trailer"])
        #expect(titles[0].displayName(number: 0) == "DVD Menu")
        #expect(MediaTitle(id: 0, isMenu: true).displayName(number: 0) == "Menu")
        #expect(titles[1].details == "1:52:04 \u{00B7} 24 chapters")
        #expect(titles[2].details == "12:34")
        #expect(titles[0].details == nil)
    }

    @Test func mainFeatureIsTheLongestTitleThatIsNotAMenu() {
        #expect(MediaTitle.mainFeature(in: titles)?.id == 1)
        #expect(MediaTitle.mainFeature(in: [titles[0]]) == nil)
        #expect(MediaTitle.offersChoice(titles))
        #expect(!MediaTitle.offersChoice(Array(titles.prefix(2))))
    }

    @Test func discsRouteToVLC() {
        var item = PlaybackItem(url: URL(filePath: "/Movies/Heat (1995)"), kind: .video)
        item.disc = .dvd
        let decision = EngineRouter().quickDecision(for: item)
        #expect(decision == EngineRouter.Decision(engine: .vlc, reason: .disc(.dvd)))
        #expect(EngineRouter.Reason.disc(.bluray).explanation == "Blu-ray discs play with VLC, menus included")
    }
}
