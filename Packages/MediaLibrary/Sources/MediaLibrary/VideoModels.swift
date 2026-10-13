import Foundation
import MetadataProviders
import SwiftData

/// Movie, TV episode or home video.
public enum VideoKind: String, Sendable, Codable, CaseIterable, Identifiable {
    case movie
    case episode
    case homeVideo

    public var id: Self { self }

    public var title: String {
        switch self {
        case .movie: "Movie"
        case .episode: "TV Episode"
        case .homeVideo: "Home Video"
        }
    }

    init(_ kind: VideoName.Kind) {
        switch kind {
        case .movie: self = .movie
        case .episode: self = .episode
        case .homeVideo: self = .homeVideo
        }
    }
}

/// Where a video's or show's details came from, and whether to look it up.
public enum MatchState: String, Sendable, Codable {
    /// Waiting for a lookup.
    case pending
    /// Details and artwork from TMDB.
    case matched
    /// Details and artwork from the free sources (TVmaze for shows, Wikipedia
    /// for movies), found without a TMDB key. TMDB improves them once a key is set.
    case keyless
    /// The user chose the TMDB entry (Fix Match).
    case manual
    /// Nothing close enough was found; names and local files are used.
    case notFound
    /// Never looked up: home videos.
    case local
}

/// Fields Edit Info can change on videos and shows. Rescans and lookups
/// leave edited fields alone; `.nfo` files fill "local" fields the same way.
public enum VideoField: String, Sendable, CaseIterable {
    case kind, title, year, overview, genres, show, season, episode, artwork, contentRating, releaseDate, cast, runtime
}

/// Someone in a movie or show's cast.
public struct CastMember: Codable, Sendable, Hashable, Identifiable {
    public var name: String
    public var role: String?
    public var imageURL: URL?

    public init(name: String, role: String? = nil, imageURL: URL? = nil) {
        self.name = name
        self.role = role
        self.imageURL = imageURL
    }

    public var id: String { name + "|" + (role ?? "") }
}

/// A movie, a TV episode or a home video: one per video file.
///
/// Values the lists need (title, show name, numbers) are stored here so grids
/// and search never have to walk relationships.
@Model
public final class Video {
    #Index<Video>([\.id], [\.kindRaw, \.sortTitle], [\.kindRaw, \.dateAdded], [\.matchStateRaw], [\.tmdbID])

    public var id: UUID = UUID()
    public var kindRaw: String = VideoKind.homeVideo.rawValue
    public var title: String = ""
    public var sortTitle: String = ""
    public var originalTitle: String?
    public var year: Int?
    /// "1995-12-15": release date, or an episode's first air date.
    public var releaseDate: String?
    public var overview: String?
    public var tagline: String?
    /// Running time in seconds from TMDB or an `.nfo` (the file's own length is `MediaFile.duration`).
    public var runtime: Double?
    public var genres: [String] = []
    public var contentRating: String?
    /// TMDB's average rating, 0–10.
    public var rating: Double?
    /// JSON-encoded `[CastMember]`.
    public var castData: Data?
    public var directors: [String] = []
    public var studio: String?
    /// "Director's Cut"…
    public var edition: String?
    /// One piece of a movie split across files.
    public var part: Int?
    public var tmdbID: Int?
    public var imdbID: String?

    // Episodes. `showTitle` mirrors the show's title for lists and search.
    public var showTitle: String?
    public var seasonNumber: Int?
    public var episodeNumber: Int?
    public var lastEpisodeNumber: Int?

    // Artwork, as `ArtworkStore` keys.
    public var posterKey: String?
    public var backdropKey: String?
    /// An episode's still (from TMDB or a `-thumb.jpg`).
    public var stillKey: String?
    /// A frame Coreplay took from the video itself.
    public var thumbnailKey: String?
    public var thumbnailAttempts: Int = 0
    /// What the user chose: an image they added, or a frame they picked.
    public var customArtworkKey: String?

    public var matchStateRaw: String = MatchState.pending.rawValue
    public var lastMatchAttempt: Date?
    /// Fields the user changed (`VideoField` raw values).
    public var editedFields: [String] = []
    /// Fields an `.nfo` file supplied; lookups don't replace them.
    public var localFields: [String] = []
    public var dateAdded: Date = Date.now

    public var file: MediaFile?
    public var show: TVShow?
    public var season: Season?

    public init() {}

    public var kind: VideoKind {
        get { VideoKind(rawValue: kindRaw) ?? .homeVideo }
        set { kindRaw = newValue.rawValue }
    }

    public var matchState: MatchState {
        get { MatchState(rawValue: matchStateRaw) ?? .pending }
        set { matchStateRaw = newValue.rawValue }
    }

    public var cast: [CastMember] {
        get { castData.flatMap { try? JSONDecoder().decode([CastMember].self, from: $0) } ?? [] }
        set { castData = newValue.isEmpty ? nil : try? JSONEncoder().encode(newValue) }
    }

    public var isAvailable: Bool {
        file?.isAvailable ?? false
    }

    /// The file's length, or the listed running time until the file is timed.
    public var duration: TimeInterval? {
        if let length = file?.duration, length > 0 { return length }
        return runtime
    }

    /// "Episode 4" for episodes without a title.
    public var displayTitle: String {
        if !title.isEmpty { return title }
        if kind == .episode, let episodeNumber { return "Episode \(episodeNumber)" }
        return file?.fileName ?? "Untitled"
    }

    /// "S2, E5", "S1, E1–E2", "Special 3".
    public var episodeLabel: String? {
        guard kind == .episode else { return nil }
        guard let episodeNumber else {
            return seasonNumber.map { $0 == 0 ? "Special" : "Season \($0)" }
        }
        let episodes = lastEpisodeNumber.map { $0 > episodeNumber ? "E\(episodeNumber)\u{2013}E\($0)" : nil } ?? nil
        if seasonNumber == 0 {
            return "Special \(episodeNumber)"
        }
        return "S\(seasonNumber ?? 1), \(episodes ?? "E\(episodeNumber)")"
    }

    /// Recorded date for home videos, else when it joined the library.
    public var sortDate: Date {
        file?.recordedDate ?? dateAdded
    }

    // MARK: Artwork choices

    /// For 2:3 cells: the user's choice, the poster, then (for episodes) the show's.
    public var posterArtworkKey: String? {
        customArtworkKey ?? posterKey ?? (kind == .episode ? season?.posterKey ?? show?.posterKey : nil)
    }

    /// For 16:9 cells: the user's choice, an episode still, a frame, the backdrop.
    public var stillArtworkKey: String? {
        customArtworkKey ?? stillKey ?? thumbnailKey ?? backdropKey ?? (kind == .episode ? show?.backdropKey : nil)
    }

    /// For the top of a detail page.
    public var backdropArtworkKey: String? {
        backdropKey ?? (kind == .episode ? show?.backdropKey : nil) ?? customArtworkKey ?? stillKey ?? thumbnailKey
    }

    /// True when there's nothing better than a generated frame for posters.
    public var needsGeneratedPoster: Bool {
        posterArtworkKey == nil
    }

    /// Episodes in airing order: by season (specials last), episode, then title.
    public static func episodeOrder(_ lhs: Video, _ rhs: Video) -> Bool {
        let leftSeason = lhs.seasonNumber.map { $0 == 0 ? Int.max : $0 } ?? Int.max - 1
        let rightSeason = rhs.seasonNumber.map { $0 == 0 ? Int.max : $0 } ?? Int.max - 1
        if leftSeason != rightSeason { return leftSeason < rightSeason }
        switch (lhs.episodeNumber, rhs.episodeNumber) {
        case let (left?, right?) where left != right: return left < right
        case (.some, nil): return true
        case (nil, .some): return false
        default: return lhs.sortTitle < rhs.sortTitle
        }
    }
}

/// A TV show: the episodes whose names (or folders) name the same show.
@Model
public final class TVShow {
    #Index<TVShow>([\.id], [\.key], [\.sortTitle], [\.dateAdded])

    public var id: UUID = UUID()
    /// Grouping key: the normalised title, plus the year when names carry one.
    public var key: String = ""
    public var title: String = ""
    public var sortTitle: String = ""
    public var year: Int?
    public var overview: String?
    public var genres: [String] = []
    public var contentRating: String?
    public var network: String?
    public var rating: Double?
    public var castData: Data?
    public var tmdbID: Int?
    public var imdbID: String?
    public var posterKey: String?
    public var backdropKey: String?
    public var customArtworkKey: String?
    public var matchStateRaw: String = MatchState.pending.rawValue
    public var lastMatchAttempt: Date?
    public var editedFields: [String] = []
    public var localFields: [String] = []
    public var dateAdded: Date = Date.now

    @Relationship(deleteRule: .cascade, inverse: \Season.show)
    public var seasons: [Season] = []
    @Relationship(deleteRule: .nullify, inverse: \Video.show)
    public var episodes: [Video] = []

    public init() {}

    public var matchState: MatchState {
        get { MatchState(rawValue: matchStateRaw) ?? .pending }
        set { matchStateRaw = newValue.rawValue }
    }

    public var cast: [CastMember] {
        get { castData.flatMap { try? JSONDecoder().decode([CastMember].self, from: $0) } ?? [] }
        set { castData = newValue.isEmpty ? nil : try? JSONEncoder().encode(newValue) }
    }

    public var posterArtworkKey: String? {
        customArtworkKey ?? posterKey
    }

    /// Seasons in order, specials last (as the TV app lists them).
    public var orderedSeasons: [Season] {
        seasons.sorted { ($0.number == 0 ? Int.max : $0.number) < ($1.number == 0 ? Int.max : $1.number) }
    }

    public var orderedEpisodes: [Video] {
        episodes.sorted(by: Video.episodeOrder)
    }
}

/// One season of a show (season 0 holds the specials).
@Model
public final class Season {
    #Index<Season>([\.id], [\.key])

    public var id: UUID = UUID()
    /// The show's key and the season number.
    public var key: String = ""
    public var number: Int = 0
    public var title: String?
    public var overview: String?
    public var posterKey: String?
    public var year: Int?

    public var show: TVShow?
    @Relationship(deleteRule: .nullify, inverse: \Video.season)
    public var episodes: [Video] = []

    public init() {}

    /// "Season 2", "Specials", or TMDB's own name ("Series 2").
    public var displayTitle: String {
        if let title, !title.isEmpty { return title }
        return number == 0 ? "Specials" : "Season \(number)"
    }

    public var orderedEpisodes: [Video] {
        episodes.sorted(by: Video.episodeOrder)
    }
}
