import Foundation
import PlaybackCore
import SwiftData

// The library as Milestone 3 shipped it, frozen.
//
// SwiftData identifies a store's version by comparing it with each schema in
// `LibraryMigrationPlan`, so these copies must stay exactly as they were:
// same entities, attributes, defaults, relationships and indexes. Never edit
// them; `MigrationTests` checks them against a real version 1 store.
extension LibrarySchemaV1 {
    @Model
    final class Source {
        #Index<Source>([\.id])

        var id: UUID = UUID()
        var name: String = ""
        var kindRaw: String = SourceKind.folder.rawValue
        var bookmarkData: Data?
        var lastKnownPath: String = ""
        var dateAdded: Date = Date.now
        var lastScanDate: Date?
        var isAvailable: Bool = true
        var audioFileCount: Int = 0
        var videoFileCount: Int = 0

        @Relationship(deleteRule: .cascade, inverse: \MediaFile.source)
        var files: [MediaFile] = []

        init() {}
    }

    @Model
    final class MediaFile {
        #Index<MediaFile>([\.id], [\.relativePath], [\.contentKey])

        var id: UUID = UUID()
        var relativePath: String = ""
        var fileName: String = ""
        var fileExtension: String = ""
        var kindRaw: String = PlaybackItem.Kind.audio.rawValue
        var fileSize: Int64 = 0
        var modificationDate: Date = Date.distantPast
        var contentKey: String = ""
        var duration: Double?
        var isAvailable: Bool = true
        var dateAdded: Date = Date.now
        var enginePreferenceRaw: String = EnginePreference.automatic.rawValue
        var codec: String?
        var sampleRate: Int?
        var bitsPerSample: Int?
        var channels: Int?
        var bitRate: Int?
        var isLossless: Bool = false

        var source: Source?
        @Relationship(deleteRule: .cascade, inverse: \Track.file)
        var track: Track?

        init() {}
    }

    @Model
    final class Track {
        #Index<Track>([\.id], [\.sortTitle])

        var id: UUID = UUID()
        var title: String = ""
        var sortTitle: String = ""
        var artistName: String = ""
        var albumTitle: String = ""
        var albumArtistName: String = ""
        var genreName: String?
        var composer: String?
        var trackNumber: Int?
        var trackCount: Int?
        var discNumber: Int?
        var discCount: Int?
        var year: Int?
        var duration: Double?
        var lyrics: String?
        var isCompilation: Bool = false
        var artworkKey: String?
        var dateAdded: Date = Date.now
        var editedFields: [String] = []

        var file: MediaFile?
        var album: Album?
        var artist: Artist?
        var genre: Genre?

        init() {}
    }

    @Model
    final class Album {
        #Index<Album>([\.key], [\.sortTitle], [\.dateAdded])

        var id: UUID = UUID()
        var key: String = ""
        var title: String = ""
        var sortTitle: String = ""
        var artistName: String = ""
        var sortArtistName: String = ""
        var year: Int?
        var genreName: String?
        var isCompilation: Bool = false
        var artworkKey: String?
        var dateAdded: Date = Date.now

        var artist: Artist?
        @Relationship(deleteRule: .nullify, inverse: \Track.album)
        var tracks: [Track] = []

        init() {}
    }

    @Model
    final class Artist {
        #Index<Artist>([\.key], [\.sortName])

        var id: UUID = UUID()
        var key: String = ""
        var name: String = ""
        var sortName: String = ""
        var artworkKey: String?

        @Relationship(deleteRule: .nullify, inverse: \Album.artist)
        var albums: [Album] = []
        @Relationship(deleteRule: .nullify, inverse: \Track.artist)
        var tracks: [Track] = []

        init() {}
    }

    @Model
    final class Genre {
        #Index<Genre>([\.key])

        var id: UUID = UUID()
        var key: String = ""
        var name: String = ""

        @Relationship(deleteRule: .nullify, inverse: \Track.genre)
        var tracks: [Track] = []

        init() {}
    }

    @Model
    final class PlaybackRecord {
        #Index<PlaybackRecord>([\.contentKey], [\.lastPlayedDate])

        var contentKey: String = ""
        var playCount: Int = 0
        var lastPlayedDate: Date?
        var position: Double?
        var rating: Int?
        var isFavorite: Bool = false

        init() {}
    }
}
