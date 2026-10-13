import Foundation
import MetadataProviders
import PlaybackCore
import SwiftData

// The library's SwiftData model (schema version 2).
//
// `MediaFile` is the physical file. `Track` and the grouping models (`Album`,
// `Artist`, `Genre`) sit on top for music; `Video` with `TVShow` and `Season`
// for movies, episodes and home videos (VideoModels.swift). Playlists join in
// Milestone 8. Play counts, positions, watched state and ratings live in
// `PlaybackRecord`, keyed by a content fingerprint rather than a path, so they
// survive moving or renaming a file (and can sync later on their own).
//
// Every attribute has a default value or is optional, which keeps
// lightweight migrations (and a future CloudKit-synced store) possible.
// Changing a model means a new schema version: see MediaLibrary.swift.

/// Where files come from.
public enum SourceKind: String, Codable, Sendable, CaseIterable {
    /// The app's own Documents folder ("On My iPhone ▸ Coreplay", Finder file sharing).
    case appDocuments
    /// A folder the user picked, kept with a security-scoped bookmark.
    case folder
    /// A single file the user added, kept with a security-scoped bookmark.
    case file
    /// The Mac's Music folder (sandbox entitlement, no bookmark needed).
    case musicFolder
    /// The Mac's Movies folder.
    case moviesFolder
}

@Model
public final class Source {
    #Index<Source>([\.id])

    public var id: UUID = UUID()
    public var name: String = ""
    public var kindRaw: String = SourceKind.folder.rawValue
    public var bookmarkData: Data?
    /// Where the source was last found, for display only.
    public var lastKnownPath: String = ""
    public var dateAdded: Date = Date.now
    public var lastScanDate: Date?
    public var isAvailable: Bool = true
    public var audioFileCount: Int = 0
    public var videoFileCount: Int = 0
    /// What the user said the folder's videos are (`VideoContentHint`).
    public var videoHintRaw: String = VideoContentHint.automatic.rawValue

    @Relationship(deleteRule: .cascade, inverse: \MediaFile.source)
    public var files: [MediaFile] = []

    public init(name: String, kind: SourceKind, bookmarkData: Data? = nil, path: String) {
        self.name = name
        self.kindRaw = kind.rawValue
        self.bookmarkData = bookmarkData
        self.lastKnownPath = path
    }

    public var kind: SourceKind {
        SourceKind(rawValue: kindRaw) ?? .folder
    }

    public var videoHint: VideoContentHint {
        get { VideoContentHint(rawValue: videoHintRaw) ?? .automatic }
        set { videoHintRaw = newValue.rawValue }
    }
}

@Model
public final class MediaFile {
    #Index<MediaFile>([\.id], [\.relativePath], [\.contentKey])

    public var id: UUID = UUID()
    /// Path below the source's root ("" for single-file sources).
    public var relativePath: String = ""
    public var fileName: String = ""
    public var fileExtension: String = ""
    public var kindRaw: String = PlaybackItem.Kind.audio.rawValue
    public var fileSize: Int64 = 0
    public var modificationDate: Date = Date.distantPast
    /// A fingerprint of size and the first and last 64 KB (see `ContentKey`).
    public var contentKey: String = ""
    public var duration: Double?
    /// `false` while the file can't be found (deleted, or its drive unplugged).
    public var isAvailable: Bool = true
    public var dateAdded: Date = Date.now
    public var enginePreferenceRaw: String = EnginePreference.automatic.rawValue
    public var codec: String?
    public var sampleRate: Int?
    public var bitsPerSample: Int?
    public var channels: Int?
    public var bitRate: Int?
    public var isLossless: Bool = false

    // Video details, read from the container (`VideoProbe`).
    public var width: Int?
    public var height: Int?
    public var frameRate: Double?
    public var videoCodec: String?
    public var audioCodec: String?
    /// `VideoInfo.DynamicRange` raw value.
    public var dynamicRangeRaw: String?
    public var hasAtmos: Bool = false
    /// Comma-separated language codes of the audio and subtitle tracks.
    public var audioLanguages: String?
    public var subtitleLanguages: String?
    public var hasSubtitles: Bool = false
    public var hasSDHSubtitles: Bool = false
    /// When and where a camera or phone recorded it.
    public var recordedDate: Date?
    public var location: String?
    /// Bumped when the video reader learns more, so old files are read again.
    public var videoProbeVersion: Int = 0

    public var source: Source?
    @Relationship(deleteRule: .cascade, inverse: \Track.file)
    public var track: Track?
    @Relationship(deleteRule: .cascade, inverse: \Video.file)
    public var video: Video?

    public init() {}

    public var kind: PlaybackItem.Kind {
        PlaybackItem.Kind(rawValue: kindRaw) ?? .unknown
    }

    public var enginePreference: EnginePreference {
        get { EnginePreference(rawValue: enginePreferenceRaw) ?? .automatic }
        set { enginePreferenceRaw = newValue.rawValue }
    }

    public var dynamicRange: VideoInfo.DynamicRange? {
        dynamicRangeRaw.flatMap(VideoInfo.DynamicRange.init(rawValue:))
    }

    /// "4K", "HD" or "SD".
    public var resolutionBadge: String? {
        var info = VideoInfo(container: "")
        info.width = width
        info.height = height
        return info.resolutionBadge
    }

    /// "Hi-Res Lossless", "Lossless" or nil, as Apple Music labels files.
    public var qualityBadge: String? {
        guard isLossless else { return nil }
        if (bitsPerSample ?? 0) > 16 || (sampleRate ?? 0) > 48_000 {
            return "Hi-Res Lossless"
        }
        return "Lossless"
    }
}

/// A song. Values are denormalised (artist and album names are stored on the
/// track too) so lists and search never need to touch the relationships.
@Model
public final class Track {
    #Index<Track>([\.id], [\.sortTitle])

    public var id: UUID = UUID()
    public var title: String = ""
    public var sortTitle: String = ""
    public var artistName: String = ""
    public var albumTitle: String = ""
    public var albumArtistName: String = ""
    public var genreName: String?
    public var composer: String?
    public var trackNumber: Int?
    public var trackCount: Int?
    public var discNumber: Int?
    public var discCount: Int?
    public var year: Int?
    public var duration: Double?
    public var lyrics: String?
    public var isCompilation: Bool = false
    /// Key into `ArtworkStore`.
    public var artworkKey: String?
    public var dateAdded: Date = Date.now
    /// Fields the user changed with Edit Info. Rescans never overwrite them.
    public var editedFields: [String] = []

    public var file: MediaFile?
    public var album: Album?
    public var artist: Artist?
    public var genre: Genre?

    public init() {}

    public var isAvailable: Bool {
        file?.isAvailable ?? false
    }
}

@Model
public final class Album {
    #Index<Album>([\.key], [\.sortTitle], [\.dateAdded])

    public var id: UUID = UUID()
    /// Grouping key: album artist (or "compilation") and title, normalised.
    public var key: String = ""
    public var title: String = ""
    public var sortTitle: String = ""
    public var artistName: String = ""
    public var sortArtistName: String = ""
    public var year: Int?
    public var genreName: String?
    public var isCompilation: Bool = false
    public var artworkKey: String?
    public var dateAdded: Date = Date.now

    public var artist: Artist?
    @Relationship(deleteRule: .nullify, inverse: \Track.album)
    public var tracks: [Track] = []

    public init() {}

    /// Tracks in disc and track order, then by title.
    public var orderedTracks: [Track] {
        tracks.sorted(by: Album.trackOrder)
    }

    public var totalDuration: TimeInterval {
        tracks.reduce(0) { $0 + ($1.duration ?? 0) }
    }

    /// More than one disc number among the tracks.
    public var hasMultipleDiscs: Bool {
        Set(tracks.map { $0.discNumber ?? 1 }).count > 1
    }

    public static func trackOrder(_ lhs: Track, _ rhs: Track) -> Bool {
        let leftDisc = lhs.discNumber ?? 1
        let rightDisc = rhs.discNumber ?? 1
        if leftDisc != rightDisc { return leftDisc < rightDisc }
        switch (lhs.trackNumber, rhs.trackNumber) {
        case let (left?, right?) where left != right: return left < right
        case (.some, nil): return true
        case (nil, .some): return false
        default: return lhs.sortTitle < rhs.sortTitle
        }
    }
}

@Model
public final class Artist {
    #Index<Artist>([\.key], [\.sortName])

    public var id: UUID = UUID()
    public var key: String = ""
    public var name: String = ""
    public var sortName: String = ""
    public var artworkKey: String?

    @Relationship(deleteRule: .nullify, inverse: \Album.artist)
    public var albums: [Album] = []
    @Relationship(deleteRule: .nullify, inverse: \Track.artist)
    public var tracks: [Track] = []

    public init() {}

    public var sortedAlbums: [Album] {
        albums.sorted { ($0.year ?? 0, $0.sortTitle) > ($1.year ?? 0, $1.sortTitle) }
    }
}

@Model
public final class Genre {
    #Index<Genre>([\.key])

    public var id: UUID = UUID()
    public var key: String = ""
    public var name: String = ""

    @Relationship(deleteRule: .nullify, inverse: \Track.genre)
    public var tracks: [Track] = []

    public init() {}

    /// The albums with songs in this genre, by title.
    public var albums: [Album] {
        var seen = Set<PersistentIdentifier>()
        var result: [Album] = []
        for track in tracks {
            guard let album = track.album, seen.insert(album.persistentModelID).inserted else { continue }
            result.append(album)
        }
        return result.sorted { $0.sortTitle < $1.sortTitle }
    }
}

/// Play history for a file, keyed by its content fingerprint. Only the main
/// context writes these (scans never touch them).
@Model
public final class PlaybackRecord {
    #Index<PlaybackRecord>([\.contentKey], [\.lastPlayedDate])

    public var contentKey: String = ""
    public var playCount: Int = 0
    public var lastPlayedDate: Date?
    /// Resume position in seconds, for videos past their first minute.
    public var position: Double?
    public var rating: Int?
    public var isFavorite: Bool = false
    /// Watched to the end credits (or marked as watched).
    public var isWatched: Bool = false
    public var watchedDate: Date?
    /// The running time when the position was saved, for progress bars.
    public var duration: Double?

    public init(contentKey: String) {
        self.contentKey = contentKey
    }
}
