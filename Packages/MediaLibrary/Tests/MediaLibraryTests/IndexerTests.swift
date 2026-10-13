import CoreGraphics
import Foundation
import ImageIO
import SwiftData
import Testing
import UniformTypeIdentifiers
@testable import MediaLibrary

/// Scans real folders of synthetic MP3s into an in-memory library.
@Suite("Library scanning", .serialized)
struct IndexerTests {
    // MARK: Fixtures

    private static func be32(_ value: Int) -> [UInt8] {
        [UInt8(value >> 24 & 0xFF), UInt8(value >> 16 & 0xFF), UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)]
    }

    private static func syncsafe(_ value: Int) -> [UInt8] {
        [UInt8(value >> 21 & 0x7F), UInt8(value >> 14 & 0x7F), UInt8(value >> 7 & 0x7F), UInt8(value & 0x7F)]
    }

    private static func frame(_ id: String, _ text: String) -> [UInt8] {
        let body: [UInt8] = [0] + Array(text.utf8)
        return Array(id.utf8) + be32(body.count) + [0, 0] + body
    }

    private static func pictureFrame(_ image: [UInt8]) -> [UInt8] {
        var body: [UInt8] = [0]
        body += Array("image/png".utf8)
        body += [0, 3, 0]
        body += image
        return Array("APIC".utf8) + be32(body.count) + [0, 0] + body
    }

    /// An MP3: ID3v2.3 tag plus ten 128 kbps frames (about a quarter second).
    private static func mp3(_ fields: [String: String], artwork: [UInt8]? = nil) -> Data {
        var frames: [UInt8] = []
        for (id, value) in fields.sorted(by: { $0.key < $1.key }) {
            frames += frame(id, value)
        }
        if let artwork {
            frames += pictureFrame(artwork)
        }
        var file: [UInt8] = Array("ID3".utf8) + [3, 0, 0] + syncsafe(frames.count) + frames
        let header: [UInt8] = [0xFF, 0xFB, 0x90, 0x00]
        for _ in 0..<10 {
            file += header + [UInt8](repeating: 0x11, count: 417 - 4)
        }
        return Data(file)
    }

    private static func pngImage() throws -> [UInt8] {
        let context = try #require(CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.9, green: 0.4, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        let image = try #require(context.makeImage())
        let output = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(output as CFMutableData, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return [UInt8](output as Data)
    }

    private struct Harness {
        let container: ModelContainer
        let indexer: LibraryIndexer
        let root: URL
        let sourceID: UUID
        let store: ArtworkStore

        init() throws {
            container = try LibraryStore.makeContainer(inMemory: true)
            indexer = LibraryIndexer(modelContainer: container)
            root = FileManager.default.temporaryDirectory.appending(path: "coreplay-scan-\(UUID().uuidString)", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            store = ArtworkStore(directory: root.appending(path: ".artwork", directoryHint: .isDirectory))
            let context = ModelContext(container)
            let source = Source(name: "Test", kind: .folder, path: root.path(percentEncoded: false))
            context.insert(source)
            try context.save()
            sourceID = source.id
        }

        func write(_ path: String, _ data: Data) throws {
            let url = root.appending(path: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
        }

        @discardableResult
        func scan() async throws -> ScanSummary {
            try await indexer.scan(sourceID: sourceID, root: root, isSingleFile: false, artworkStore: store) { _ in }
        }

        func fetch<Model: PersistentModel>(_ type: Model.Type) throws -> [Model] {
            try ModelContext(container).fetch(FetchDescriptor<Model>())
        }

        func cleanUp() {
            try? FileManager.default.removeItem(at: root)
        }
    }

    // MARK: Tests

    @Test func scansTaggedAndUntaggedMusicIntoAlbums() async throws {
        let harness = try Harness()
        defer { harness.cleanUp() }
        let cover = try Self.pngImage()
        try harness.write("Massive Attack/Mezzanine/01 Angel.mp3", Self.mp3(["TIT2": "Angel", "TPE1": "Massive Attack", "TALB": "Mezzanine", "TRCK": "1", "TYER": "1998", "TCON": "Trip-Hop"], artwork: cover))
        try harness.write("Massive Attack/Mezzanine/02 Risingson.mp3", Self.mp3(["TIT2": "Risingson", "TPE1": "Massive Attack", "TALB": "Mezzanine", "TRCK": "2"]))
        try harness.write("Portishead/Dummy/03 Sour Times.mp3", Self.mp3([:]))
        try harness.write("Notes/readme.txt", Data("not media".utf8))

        let summary = try await harness.scan()
        #expect(summary.added == 3)

        let tracks = try harness.fetch(Track.self)
        #expect(tracks.count == 3)
        let albums = try harness.fetch(Album.self).sorted { $0.sortTitle < $1.sortTitle }
        #expect(albums.map(\.title) == ["Dummy", "Mezzanine"])
        let mezzanine = try #require(albums.last)
        #expect(mezzanine.tracks.count == 2)
        #expect(mezzanine.artistName == "Massive Attack")
        #expect(mezzanine.year == 1998)
        #expect(mezzanine.orderedTracks.map(\.title) == ["Angel", "Risingson"])
        let artworkKey = try #require(mezzanine.artworkKey)
        #expect(harness.store.contains(artworkKey))

        // The untagged file falls back to its folders and file name.
        let sourTimes = try #require(tracks.first { $0.title == "Sour Times" })
        #expect(sourTimes.artistName == "Portishead")
        #expect(sourTimes.albumTitle == "Dummy")
        #expect(sourTimes.trackNumber == 3)

        let artists = try harness.fetch(Artist.self).map(\.name).sorted()
        #expect(artists == ["Massive Attack", "Portishead"])
        #expect(try harness.fetch(Genre.self).map(\.name) == ["Trip-Hop"])
        let files = try harness.fetch(MediaFile.self)
        #expect(files.allSatisfy { $0.duration != nil && !$0.contentKey.isEmpty })
    }

    @Test func rescansOnlyReadChangedFilesAndMarkMissingOnes() async throws {
        let harness = try Harness()
        defer { harness.cleanUp() }
        try harness.write("A/Album/01 One.mp3", Self.mp3(["TIT2": "One", "TPE1": "A", "TALB": "Album"]))
        try harness.write("A/Album/02 Two.mp3", Self.mp3(["TIT2": "Two", "TPE1": "A", "TALB": "Album"]))
        try await harness.scan()

        let second = try await harness.scan()
        #expect(second.unchanged == 2)
        #expect(second.added == 0)
        #expect(second.updated == 0)

        try FileManager.default.removeItem(at: harness.root.appending(path: "A/Album/02 Two.mp3"))
        // Retag the first file (a different size, so it's picked up even within the same second).
        try harness.write("A/Album/01 One.mp3", Self.mp3(["TIT2": "One (Remastered)", "TPE1": "A", "TALB": "Album", "TRCK": "1"]))
        let third = try await harness.scan()
        #expect(third.updated == 1)
        #expect(third.missing == 1)

        let tracks = try harness.fetch(Track.self)
        #expect(tracks.count == 2) // the missing one is kept, marked unavailable
        #expect(tracks.contains { $0.title == "One (Remastered)" })
        let missing = try #require(tracks.first { $0.title == "Two" })
        #expect(missing.isAvailable == false)
    }

    @Test func compilationsGroupUnderOneAlbum() async throws {
        let harness = try Harness()
        defer { harness.cleanUp() }
        try harness.write("Comp/01.mp3", Self.mp3(["TIT2": "First", "TPE1": "Artist One", "TALB": "Summer Hits", "TCMP": "1"]))
        try harness.write("Comp/02.mp3", Self.mp3(["TIT2": "Second", "TPE1": "Artist Two", "TALB": "Summer Hits", "TCMP": "1"]))
        try await harness.scan()
        let albums = try harness.fetch(Album.self)
        #expect(albums.count == 1)
        #expect(albums.first?.isCompilation == true)
        #expect(albums.first?.artistName == "Various Artists")
        #expect(Set(try harness.fetch(Track.self).map(\.artistName)) == ["Artist One", "Artist Two"])
    }

    @Test func editedFieldsSurviveRescans() async throws {
        let harness = try Harness()
        defer { harness.cleanUp() }
        try harness.write("X/Y/01 Song.mp3", Self.mp3(["TIT2": "Sng", "TPE1": "X", "TALB": "Y"]))
        try await harness.scan()

        let context = ModelContext(harness.container)
        let track = try #require(try context.fetch(FetchDescriptor<Track>()).first)
        track.title = "Song"
        track.editedFields = [TrackField.title.rawValue]
        try context.save()

        // Touch the file so it's read again.
        try harness.write("X/Y/01 Song.mp3", Self.mp3(["TIT2": "Sng", "TPE1": "X", "TALB": "Y", "TRCK": "1"]))
        try await harness.scan()
        let rescanned = try #require(try harness.fetch(Track.self).first)
        #expect(rescanned.title == "Song")
        #expect(rescanned.trackNumber == 1)
    }

    @Test func retaggingMovesTracksAndRemovesEmptyAlbums() async throws {
        let harness = try Harness()
        defer { harness.cleanUp() }
        try harness.write("S/01.mp3", Self.mp3(["TIT2": "Song", "TPE1": "Band", "TALB": "Old Name"]))
        try await harness.scan()
        try harness.write("S/01.mp3", Self.mp3(["TIT2": "Song", "TPE1": "Band", "TALB": "New Name", "TRCK": "1"]))
        try await harness.scan()
        #expect(try harness.fetch(Album.self).map(\.title) == ["New Name"])
    }

    @Test func removingASourceRemovesItsMusic() async throws {
        let harness = try Harness()
        defer { harness.cleanUp() }
        try harness.write("B/C/01.mp3", Self.mp3(["TIT2": "Gone", "TPE1": "B", "TALB": "C"]))
        try await harness.scan()
        try await harness.indexer.removeSource(id: harness.sourceID)
        #expect(try harness.fetch(Track.self).isEmpty)
        #expect(try harness.fetch(Album.self).isEmpty)
        #expect(try harness.fetch(Artist.self).isEmpty)
        #expect(try harness.fetch(MediaFile.self).isEmpty)
    }

    @Test func folderArtworkIsUsedWhenFilesHaveNone() async throws {
        let harness = try Harness()
        defer { harness.cleanUp() }
        try harness.write("D/E/01.mp3", Self.mp3(["TIT2": "Plain", "TPE1": "D", "TALB": "E"]))
        try harness.write("D/E/cover.png", Data(try Self.pngImage()))
        try await harness.scan()
        let album = try #require(try harness.fetch(Album.self).first)
        #expect(album.artworkKey != nil)
    }
}
