import CoreData
import Foundation
import PlaybackCore
import SwiftData
import Testing
@testable import MediaLibrary

extension LibraryTests {
    /// Upgrades a real version 1 library: `Fixtures/LibraryV1/Library.store` was
    /// written by the Milestone 3 app's own schema (a source, a song with an
    /// edited title and seven plays, and a video with a resume position).
    @Suite("Library upgrades", .serialized)
    struct MigrationTests {
        private static func fixtureCopy() throws -> URL {
            let folder = try #require(Bundle.module.url(forResource: "LibraryV1", withExtension: nil))
            let temp = FileManager.default.temporaryDirectory.appending(path: "coreplay-migration-\(UUID().uuidString)", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
            let store = temp.appending(path: "Library.store")
            try FileManager.default.copyItem(at: folder.appending(path: "Library.store"), to: store)
            return store
        }

        /// The frozen version 1 models must describe exactly what Milestone 3
        /// wrote, or SwiftData can't tell which version an old library is.
        @Test func frozenSchemaMatchesVersion1Stores() throws {
            let store = try Self.fixtureCopy()
            let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(type: .sqlite, at: store)
            let storeHashes = try #require(metadata[NSStoreModelVersionHashesKey] as? [String: Data])
            let model = try #require(NSManagedObjectModel.makeManagedObjectModel(for: LibrarySchemaV1.models))
            #expect(model.entityVersionHashesByName == storeHashes)
            #expect(model.versionChecksum == metadata["NSStoreModelVersionChecksumKey"] as? String)

            // And version 2 really is different.
            let current = try #require(NSManagedObjectModel.makeManagedObjectModel(for: LibrarySchemaV2.models))
            #expect(current.entityVersionHashesByName != storeHashes)
        }

        @Test @MainActor func upgradesVersion1StoresInPlace() throws {
            let store = try Self.fixtureCopy()
            do {
                let container = try LibraryStore.makeContainer(url: store)
                let context = ModelContext(container)

                let sources = try context.fetch(FetchDescriptor<MediaLibrary.Source>())
                #expect(sources.count == 1)
                let source = try #require(sources.first)
                #expect(source.name == "Music")
                #expect(source.bookmarkData == Data([1, 2, 3, 4]))
                #expect(source.audioFileCount == 1)
                #expect(source.videoHint == .automatic)

                let tracks = try context.fetch(FetchDescriptor<MediaLibrary.Track>())
                let track = try #require(tracks.first)
                #expect(track.title == "Angel (Edited)")
                #expect(track.editedFields == ["title"])
                #expect(track.album?.title == "Mezzanine")
                #expect(track.artist?.name == "Massive Attack")
                #expect(track.genre?.name == "Trip-Hop")
                #expect(track.file?.codec == "FLAC")
                #expect(track.file?.isLossless == true)

                let records = try context.fetch(FetchDescriptor<MediaLibrary.PlaybackRecord>(sortBy: [SortDescriptor(\.contentKey)]))
                #expect(records.map(\.contentKey) == ["song-key", "video-key"])
                #expect(records.first?.playCount == 7)
                #expect(records.first?.rating == 4)
                #expect(records.first?.isFavorite == true)
                #expect(records.last?.position == 1_234)
                #expect(records.last?.isWatched == false)

                // The old video is waiting to be read again into the video library.
                let videoKind = PlaybackItem.Kind.video.rawValue
                let videos = try context.fetch(FetchDescriptor<MediaLibrary.MediaFile>(predicate: #Predicate { $0.kindRaw == videoKind }))
                let file = try #require(videos.first)
                #expect(file.video == nil)
                #expect(file.videoProbeVersion == 0)
                #expect(file.enginePreference == .vlc)

                // Version 2 models work in the upgraded store.
                let video = Video()
                video.kind = .movie
                video.title = "Heat"
                video.year = 1995
                context.insert(video)
                file.video = video
                try context.save()
            }
            // Reopening finds everything, at the current version, with playlists.
            let reopened = try LibraryStore.makeContainer(url: store)
            let context = ModelContext(reopened)
            let video = try #require(try context.fetch(FetchDescriptor<Video>()).first)
            #expect(video.title == "Heat")
            #expect(video.file?.fileName == "Heat.1995.1080p.BluRay.mkv")
            context.insert(Playlist(name: "Kept"))
            try context.save()
            #expect(try context.fetch(FetchDescriptor<Playlist>()).map(\.name) == ["Kept"])
            let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(type: .sqlite, at: store)
            #expect((metadata["NSStoreModelVersionIdentifiers"] as? [String]) == ["3.0.0"])
        }
    }
}
