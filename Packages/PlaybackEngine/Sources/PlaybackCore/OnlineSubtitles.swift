import Foundation

/// What to look for when finding subtitles online for a video.
public struct SubtitleSearchRequest: Hashable, Sendable {
    /// The file, for its hash: subtitles made for exactly this release.
    public var fileURL: URL?
    /// The movie's title, or for an episode its show's.
    public var title: String
    public var year: Int?
    /// A movie's IMDb ID ("tt0113277").
    public var imdbID: String?
    /// An episode's show's IMDb ID.
    public var showIMDbID: String?
    public var season: Int?
    public var episode: Int?
    /// ISO 639-1 codes; empty searches every language.
    public var languages: [String]

    public init(
        fileURL: URL? = nil,
        title: String,
        year: Int? = nil,
        imdbID: String? = nil,
        showIMDbID: String? = nil,
        season: Int? = nil,
        episode: Int? = nil,
        languages: [String] = []
    ) {
        self.fileURL = fileURL
        self.title = title
        self.year = year
        self.imdbID = imdbID
        self.showIMDbID = showIMDbID
        self.season = season
        self.episode = episode
        self.languages = languages
    }
}

/// One subtitle file on offer.
public struct OnlineSubtitle: Hashable, Sendable, Identifiable {
    /// The provider's ID for the file.
    public var id: Int
    /// An ISO 639-1 code.
    public var language: String
    /// The release it was made for ("Heat.1995.1080p.BluRay").
    public var release: String
    public var downloadCount: Int
    public var isHearingImpaired: Bool
    /// Only the lines in other languages (signs, foreign dialogue).
    public var isForeignPartsOnly: Bool
    public var isMachineTranslated: Bool
    /// Made for this exact file.
    public var matchesFile: Bool

    public init(
        id: Int,
        language: String,
        release: String,
        downloadCount: Int = 0,
        isHearingImpaired: Bool = false,
        isForeignPartsOnly: Bool = false,
        isMachineTranslated: Bool = false,
        matchesFile: Bool = false
    ) {
        self.id = id
        self.language = language
        self.release = release
        self.downloadCount = downloadCount
        self.isHearingImpaired = isHearingImpaired
        self.isForeignPartsOnly = isForeignPartsOnly
        self.isMachineTranslated = isMachineTranslated
        self.matchesFile = matchesFile
    }
}

/// Finds and downloads subtitles: OpenSubtitles.com with your own key (the
/// app sets one up when a key is saved in Settings).
public protocol OnlineSubtitleProvider: Sendable {
    /// "OpenSubtitles", for the player's labels.
    var name: String { get }
    func search(_ request: SubtitleSearchRequest) async throws -> [OnlineSubtitle]
    /// Downloads one, returning a local file the player can load.
    func download(_ subtitle: OnlineSubtitle) async throws -> URL
}
