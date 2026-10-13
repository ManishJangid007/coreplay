import CoreGraphics
import Foundation
import ImageIO
import MetadataProviders
import SwiftData
import Testing
import UniformTypeIdentifiers
@testable import MediaLibrary

/// Scans folders of (fake) video files into movies, shows and home videos.
@Suite("Video library scanning", .serialized)
struct VideoIndexerTests {
    private struct Harness {
        let container: ModelContainer
        let indexer: LibraryIndexer
        let root: URL
        let sourceID: UUID
        let store: ArtworkStore

        init() throws {
            container = try LibraryStore.makeContainer(inMemory: true)
            indexer = LibraryIndexer(modelContainer: container)
            root = FileManager.default.temporaryDirectory.appending(path: "coreplay-videos-\(UUID().uuidString)", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            store = ArtworkStore(directory: FileManager.default.temporaryDirectory.appending(path: "coreplay-art-\(UUID().uuidString)", directoryHint: .isDirectory))
            let context = ModelContext(container)
            let source = Source(name: "Videos", kind: .folder, path: root.path(percentEncoded: false))
            context.insert(source)
            try context.save()
            sourceID = source.id
        }

        func write(_ path: String, _ data: Data = Data(repeating: 7, count: 2_048)) throws {
            let url = root.appending(path: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
        }

        func scan() async throws {
            _ = try await indexer.scan(sourceID: sourceID, root: root, isSingleFile: false, artworkStore: store) { _ in }
        }

        func fetch<Model: PersistentModel>(_ type: Model.Type) throws -> [Model] {
            try ModelContext(container).fetch(FetchDescriptor<Model>())
        }

        func cleanUp() {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: store.directory)
        }
    }

    private static func png(red: Double) throws -> Data {
        let context = try #require(CGContext(data: nil, width: 6, height: 9, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: red, green: 0.3, blue: 0.2, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 6, height: 9))
        let image = try #require(context.makeImage())
        let output = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(output as CFMutableData, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return output as Data
    }

    @Test func sortsVideosIntoMoviesShowsAndHomeVideos() async throws {
        let harness = try Harness()
        defer { harness.cleanUp() }
        try harness.write("Heat (1995).mkv")
        try harness.write("Heat (1995)-poster.png", Self.png(red: 0.9))
        try harness.write("Breaking Bad/Season 1/Breaking.Bad.S01E01.Pilot.720p.mkv")
        try harness.write("Breaking Bad/Season 1/Breaking.Bad.S01E02.mkv")
        try harness.write("Breaking Bad/Season 2/Breaking.Bad.S02E01.Seven.Thirty-Seven.mkv")
        try harness.write("Breaking Bad/poster.png", Self.png(red: 0.1))
        try harness.write("Breaking Bad/tvshow.nfo", Data("<tvshow><title>Breaking Bad</title><year>2008</year><uniqueid type=\"tmdb\">1396</uniqueid></tvshow>".utf8))
        try harness.write("IMG_1234.MOV")
        try await harness.scan()

        let videos = try harness.fetch(Video.self)
        #expect(videos.count == 5)
        let movie = try #require(videos.first { $0.kind == .movie })
        #expect(movie.title == "Heat")
        #expect(movie.year == 1995)
        #expect(movie.posterKey != nil)
        #expect(movie.matchState == .pending)

        let home = try #require(videos.first { $0.kind == .homeVideo })
        #expect(home.title == "IMG 1234")
        #expect(home.matchState == .local)

        let shows = try harness.fetch(TVShow.self)
        #expect(shows.count == 1)
        let show = try #require(shows.first)
        #expect(show.title == "Breaking Bad")
        #expect(show.tmdbID == 1396)
        #expect(show.year == 2008)
        #expect(show.posterKey != nil)
        #expect(show.episodes.count == 3)
        #expect(show.orderedSeasons.map(\.number) == [1, 2])
        let pilot = try #require(show.orderedEpisodes.first)
        #expect(pilot.title == "Pilot")
        #expect(pilot.episodeLabel == "S1, E1")
        #expect(pilot.showTitle == "Breaking Bad")
        #expect(show.orderedEpisodes.map(\.episodeLabel) == ["S1, E1", "S1, E2", "S2, E1"])
    }

    @Test func editsSurviveAndFolderContentReclassifies() async throws {
        let harness = try Harness()
        defer { harness.cleanUp() }
        try harness.write("Party.mp4")
        try harness.write("Firefly/S01E01.mkv")
        try await harness.scan()

        let home = try #require(try harness.fetch(Video.self).first { $0.kind == .homeVideo })
        var edit = VideoEdit(video: home)
        edit.kind = .movie
        edit.title = "Serenity"
        edit.year = 2005
        try await harness.indexer.applyVideoEdit(edit, videoID: home.id)

        // Everything in the folder is a home video now, except what the user said.
        try await harness.indexer.setVideoHint(sourceID: harness.sourceID, hint: .homeVideos)
        try await harness.scan()
        let videos = try harness.fetch(Video.self)
        let edited = try #require(videos.first { $0.title == "Serenity" })
        #expect(edited.kind == .movie)
        #expect(edited.year == 2005)
        #expect(Set(edited.editedFields).isSuperset(of: ["kind", "title", "year"]))
        #expect(videos.filter { $0.kind == .homeVideo }.count == 1)
        // The show lost its only episode.
        #expect(try harness.fetch(TVShow.self).isEmpty)
        #expect(try harness.fetch(Season.self).isEmpty)
    }

    @Test func customArtworkAndLookupRequests() async throws {
        let harness = try Harness()
        defer { harness.cleanUp() }
        try harness.write("Heat (1995).mkv")
        try await harness.scan()
        let movie = try #require(try harness.fetch(Video.self).first)

        let key = try #require(harness.store.store(try Self.png(red: 0.5)))
        try await harness.indexer.setArtwork(videoID: movie.id, key: key)
        var updated = try #require(try harness.fetch(Video.self).first)
        #expect(updated.customArtworkKey == key)
        #expect(updated.posterArtworkKey == key)
        #expect(updated.editedFields.contains("artwork"))

        try await harness.indexer.setArtwork(videoID: movie.id, key: nil)
        updated = try #require(try harness.fetch(Video.self).first)
        #expect(updated.customArtworkKey == nil)
        #expect(!updated.editedFields.contains("artwork"))

        // Nothing waits forever: an unreachable key leaves items pending.
        #expect(try await harness.indexer.retryNotFound() == 0)
        let inUse = try await harness.indexer.artworkKeysInUse()
        #expect(!inUse.contains(key))
    }
}
