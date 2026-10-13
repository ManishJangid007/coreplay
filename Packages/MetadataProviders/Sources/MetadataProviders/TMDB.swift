import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The Movie Database (themoviedb.org), with the user's own API key.
///
/// Accepts either kind of credential TMDB issues: the 32-character "API key"
/// (sent as a query parameter) or the longer "API Read Access Token" (sent
/// as a bearer token). Nothing is looked up until the user adds one.
///
/// This product uses the TMDB API but is not endorsed or certified by TMDB.
public struct TMDBClient: Sendable {
    public enum Failure: LocalizedError, Equatable {
        case invalidKey
        case notFound
        case rateLimited
        case server(Int)
        case unreadableResponse

        public var errorDescription: String? {
            switch self {
            case .invalidKey: "TMDB didn\u{2019}t accept the API key. Check it in Settings."
            case .notFound: "TMDB doesn\u{2019}t have that title."
            case .rateLimited: "TMDB is busy. Coreplay will try again shortly."
            case .server(let code): "TMDB returned an error (\(code))."
            case .unreadableResponse: "TMDB sent something Coreplay couldn\u{2019}t read."
            }
        }
    }

    public static let imageBaseURL = URL(string: "https://image.tmdb.org/t/p/")!
    private static let apiBaseURL = URL(string: "https://api.themoviedb.org/3/")!

    public let key: String
    /// "en-US": titles, synopses and artwork come back in this language where TMDB has them.
    public let language: String
    /// Two-letter region for age ratings ("US", "GB", "IN").
    public let region: String
    private let session: URLSession

    public init(key: String, language: String = TMDBClient.preferredLanguage, region: String = TMDBClient.preferredRegion, session: URLSession = .shared) {
        self.key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        self.language = language
        self.region = region
        self.session = session
    }

    public static var preferredLanguage: String {
        let identifier = Locale.preferredLanguages.first ?? "en-US"
        let parts = identifier.split(whereSeparator: { $0 == "-" || $0 == "_" })
        guard let languageCode = parts.first else { return "en-US" }
        if parts.count >= 2, let regionCode = parts.last, regionCode.count == 2 {
            return "\(languageCode)-\(regionCode.uppercased())"
        }
        return String(languageCode)
    }

    public static var preferredRegion: String {
        Locale.current.region?.identifier ?? "US"
    }

    /// A v4 read access token (a JWT) rather than a v3 key.
    var usesBearerToken: Bool {
        key.count > 40
    }

    public static func imageURL(_ path: String?, size: String) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        return imageBaseURL.appending(path: size).appending(path: path.hasPrefix("/") ? String(path.dropFirst()) : path)
    }

    // MARK: - Requests

    /// Checks the key with the cheapest call TMDB has.
    public func validate() async throws {
        let _: TMDBConfiguration = try await get("configuration", query: [])
    }

    public func searchMovies(title: String, year: Int?) async throws -> [TMDBMovieResult] {
        var query = [URLQueryItem(name: "query", value: title), URLQueryItem(name: "include_adult", value: "false")]
        if let year {
            query.append(URLQueryItem(name: "year", value: String(year)))
        }
        let page: TMDBPage<TMDBMovieResult> = try await get("search/movie", query: query)
        return page.results
    }

    public func searchShows(title: String, year: Int?) async throws -> [TMDBShowResult] {
        var query = [URLQueryItem(name: "query", value: title), URLQueryItem(name: "include_adult", value: "false")]
        if let year {
            query.append(URLQueryItem(name: "first_air_date_year", value: String(year)))
        }
        let page: TMDBPage<TMDBShowResult> = try await get("search/tv", query: query)
        return page.results
    }

    public func movie(id: Int) async throws -> TMDBMovie {
        try await get("movie/\(id)", query: [URLQueryItem(name: "append_to_response", value: "credits,release_dates")])
    }

    public func show(id: Int) async throws -> TMDBShow {
        try await get("tv/\(id)", query: [URLQueryItem(name: "append_to_response", value: "credits,content_ratings")])
    }

    public func season(showID: Int, number: Int) async throws -> TMDBSeason {
        try await get("tv/\(showID)/season/\(number)", query: [])
    }

    /// Looks a title up by its IMDb ID (from an `.nfo` file).
    public func find(imdbID: String) async throws -> TMDBFindResult {
        try await get("find/\(imdbID)", query: [URLQueryItem(name: "external_source", value: "imdb_id")])
    }

    /// Downloads an image (posters, backdrops, stills).
    public func image(path: String, size: String) async throws -> Data {
        guard let url = Self.imageURL(path, size: size) else { throw Failure.notFound }
        let (data, response) = try await session.data(from: url)
        try Self.check(response)
        return data
    }

    func request(_ path: String, query: [URLQueryItem]) -> URLRequest {
        var components = URLComponents(url: Self.apiBaseURL.appending(path: path), resolvingAgainstBaseURL: false)!
        var items = query + [URLQueryItem(name: "language", value: language)]
        if !usesBearerToken {
            items.append(URLQueryItem(name: "api_key", value: key))
        }
        components.queryItems = items
        var request = URLRequest(url: components.url!)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if usesBearerToken {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        request.timeoutInterval = 20
        return request
    }

    private func get<Value: Decodable>(_ path: String, query: [URLQueryItem]) async throws -> Value {
        let request = request(path, query: query)
        var attempt = 0
        while true {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 429, attempt < 2 {
                attempt += 1
                let wait = Double(http.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 2
                try await Task.sleep(for: .seconds(min(max(wait, 1), 10)))
                continue
            }
            try Self.check(response)
            do {
                return try Self.decoder.decode(Value.self, from: data)
            } catch {
                throw Failure.unreadableResponse
            }
        }
    }

    private static func check(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        switch http.statusCode {
        case 200..<300: return
        case 401: throw Failure.invalidKey
        case 404: throw Failure.notFound
        case 429: throw Failure.rateLimited
        default: throw Failure.server(http.statusCode)
        }
    }

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()
}

// MARK: - Responses

struct TMDBConfiguration: Decodable {}

struct TMDBPage<Result: Decodable>: Decodable {
    var results: [Result]
}

public struct TMDBMovieResult: Decodable, Sendable, Equatable {
    public var id: Int
    public var title: String
    public var originalTitle: String?
    public var releaseDate: String?
    public var overview: String?
    public var posterPath: String?
    public var backdropPath: String?
    public var popularity: Double?
    public var voteCount: Int?

    public init(id: Int, title: String, originalTitle: String? = nil, releaseDate: String? = nil, overview: String? = nil, posterPath: String? = nil, backdropPath: String? = nil, popularity: Double? = nil, voteCount: Int? = nil) {
        self.id = id
        self.title = title
        self.originalTitle = originalTitle
        self.releaseDate = releaseDate
        self.overview = overview
        self.posterPath = posterPath
        self.backdropPath = backdropPath
        self.popularity = popularity
        self.voteCount = voteCount
    }

    public var year: Int? { TMDBDates.year(releaseDate) }
}

public struct TMDBShowResult: Decodable, Sendable, Equatable {
    public var id: Int
    public var name: String
    public var originalName: String?
    public var firstAirDate: String?
    public var overview: String?
    public var posterPath: String?
    public var backdropPath: String?
    public var popularity: Double?
    public var voteCount: Int?

    public init(id: Int, name: String, originalName: String? = nil, firstAirDate: String? = nil, overview: String? = nil, posterPath: String? = nil, backdropPath: String? = nil, popularity: Double? = nil, voteCount: Int? = nil) {
        self.id = id
        self.name = name
        self.originalName = originalName
        self.firstAirDate = firstAirDate
        self.overview = overview
        self.posterPath = posterPath
        self.backdropPath = backdropPath
        self.popularity = popularity
        self.voteCount = voteCount
    }

    public var year: Int? { TMDBDates.year(firstAirDate) }
}

public struct TMDBNamed: Decodable, Sendable, Equatable {
    public var name: String
}

public struct TMDBCastMember: Decodable, Sendable, Equatable {
    public var name: String
    public var character: String?
    public var profilePath: String?
    public var order: Int?
}

public struct TMDBCrewMember: Decodable, Sendable, Equatable {
    public var name: String
    public var job: String?
}

public struct TMDBCredits: Decodable, Sendable, Equatable {
    public var cast: [TMDBCastMember]?
    public var crew: [TMDBCrewMember]?
}

public struct TMDBMovie: Decodable, Sendable, Equatable {
    public struct ReleaseDates: Decodable, Sendable, Equatable {
        public struct Country: Decodable, Sendable, Equatable {
            public struct Release: Decodable, Sendable, Equatable {
                public var certification: String?
                public var type: Int?
            }

            public var iso31661: String
            public var releaseDates: [Release]
        }

        public var results: [Country]
    }

    public var id: Int
    public var title: String
    public var originalTitle: String?
    public var overview: String?
    public var tagline: String?
    public var releaseDate: String?
    /// Minutes.
    public var runtime: Int?
    public var genres: [TMDBNamed]?
    public var posterPath: String?
    public var backdropPath: String?
    public var voteAverage: Double?
    public var imdbId: String?
    public var productionCompanies: [TMDBNamed]?
    public var credits: TMDBCredits?
    public var releaseDates: ReleaseDates?

    public var year: Int? { TMDBDates.year(releaseDate) }

    /// The age rating for `region`, falling back to the US one.
    public func certification(region: String) -> String? {
        for code in [region, "US"] {
            let releases = releaseDates?.results.first { $0.iso31661 == code }?.releaseDates ?? []
            // Theatrical (3) before digital (4) and the rest.
            let sorted = releases.sorted { ($0.type ?? 9) < ($1.type ?? 9) }
            if let rating = sorted.lazy.compactMap({ $0.certification?.trimmingCharacters(in: .whitespaces) }).first(where: { !$0.isEmpty }) {
                return rating
            }
        }
        return nil
    }

    public var directors: [String] {
        (credits?.crew ?? []).filter { $0.job == "Director" }.map(\.name)
    }
}

public struct TMDBShow: Decodable, Sendable, Equatable {
    public struct Season: Decodable, Sendable, Equatable {
        public var seasonNumber: Int
        public var name: String?
        public var overview: String?
        public var posterPath: String?
        public var airDate: String?
        public var episodeCount: Int?
    }

    public struct ContentRatings: Decodable, Sendable, Equatable {
        public struct Rating: Decodable, Sendable, Equatable {
            public var iso31661: String
            public var rating: String
        }

        public var results: [Rating]
    }

    public var id: Int
    public var name: String
    public var originalName: String?
    public var overview: String?
    public var tagline: String?
    public var firstAirDate: String?
    public var episodeRunTime: [Int]?
    public var genres: [TMDBNamed]?
    public var posterPath: String?
    public var backdropPath: String?
    public var voteAverage: Double?
    public var networks: [TMDBNamed]?
    public var seasons: [Season]?
    public var credits: TMDBCredits?
    public var contentRatings: ContentRatings?

    public var year: Int? { TMDBDates.year(firstAirDate) }

    public func certification(region: String) -> String? {
        for code in [region, "US"] {
            if let rating = contentRatings?.results.first(where: { $0.iso31661 == code })?.rating, !rating.isEmpty {
                return rating
            }
        }
        return nil
    }
}

public struct TMDBSeason: Decodable, Sendable, Equatable {
    public struct Episode: Decodable, Sendable, Equatable {
        public var id: Int?
        public var episodeNumber: Int
        public var seasonNumber: Int?
        public var name: String?
        public var overview: String?
        public var airDate: String?
        public var runtime: Int?
        public var stillPath: String?
    }

    public var seasonNumber: Int?
    public var name: String?
    public var overview: String?
    public var posterPath: String?
    public var airDate: String?
    public var episodes: [Episode]?
}

public struct TMDBFindResult: Decodable, Sendable, Equatable {
    public var movieResults: [TMDBMovieResult]
    public var tvResults: [TMDBShowResult]
}

enum TMDBDates {
    static func year(_ date: String?) -> Int? {
        guard let date, date.count >= 4, let year = Int(date.prefix(4)), year > 1800 else { return nil }
        return year
    }
}

// MARK: - Matching

/// Picks the search result that is really the file's movie or show.
///
/// A result must be close in title (ignoring case, accents, punctuation and
/// a leading "The"), and the year, when the file has one, must agree within
/// a year. Matching nothing is better than matching the wrong film.
public enum TMDBMatching {
    public struct Candidate: Sendable, Equatable {
        public var id: Int
        public var titles: [String]
        public var year: Int?
        public var votes: Int

        public init(id: Int, titles: [String], year: Int?, votes: Int) {
            self.id = id
            self.titles = titles
            self.year = year
            self.votes = votes
        }
    }

    public static func bestMovie(_ results: [TMDBMovieResult], title: String, year: Int?) -> TMDBMovieResult? {
        let candidates = results.map { Candidate(id: $0.id, titles: [$0.title, $0.originalTitle].compactMap { $0 }, year: $0.year, votes: $0.voteCount ?? 0) }
        guard let id = best(candidates, title: title, year: year) else { return nil }
        return results.first { $0.id == id }
    }

    public static func bestShow(_ results: [TMDBShowResult], title: String, year: Int?) -> TMDBShowResult? {
        let candidates = results.map { Candidate(id: $0.id, titles: [$0.name, $0.originalName].compactMap { $0 }, year: $0.year, votes: $0.voteCount ?? 0) }
        guard let id = best(candidates, title: title, year: year) else { return nil }
        return results.first { $0.id == id }
    }

    public static func best(_ candidates: [Candidate], title: String, year: Int?) -> Int? {
        var bestScore = -Double.infinity
        var bestID: Int?
        for (rank, candidate) in candidates.prefix(10).enumerated() {
            let similarity = candidate.titles.map { self.similarity($0, title) }.max() ?? 0
            var score = similarity
            var yearAgrees = false
            if let year, let candidateYear = candidate.year {
                let difference = abs(year - candidateYear)
                if difference == 0 {
                    score += 0.3
                    yearAgrees = true
                } else if difference == 1 {
                    score += 0.15
                    yearAgrees = true
                } else {
                    continue // a different year is a different film (or a remake)
                }
            } else if year != nil {
                score -= 0.1 // the result has no date to check against
            }
            // Close titles only; a little looser when the year confirms it.
            guard similarity >= (yearAgrees ? 0.72 : 0.86) else { continue }
            // TMDB orders by relevance; popularity breaks near-ties.
            score += Double(min(candidate.votes, 5_000)) / 100_000 - Double(rank) * 0.01
            if score > bestScore {
                bestScore = score
                bestID = candidate.id
            }
        }
        return bestID
    }

    /// 1 for the same title, falling towards 0 as they differ.
    public static func similarity(_ lhs: String, _ rhs: String) -> Double {
        let left = normalized(lhs)
        let right = normalized(rhs)
        guard !left.isEmpty, !right.isEmpty else { return 0 }
        if left == right { return 1 }
        let distance = levenshtein(Array(left), Array(right))
        return max(0, 1 - Double(distance) / Double(max(left.count, right.count)))
    }

    /// Lowercase, no accents or punctuation, "&" as "and", no leading article.
    public static func normalized(_ title: String) -> String {
        let folded = title
            .replacingOccurrences(of: "&", with: " and ")
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
        let kept = folded.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
        var words = String(kept).split(separator: " ").map(String.init)
        if words.count > 1, ["the", "a", "an"].contains(words[0]) {
            words.removeFirst()
        }
        return words.joined(separator: " ")
    }

    static func levenshtein(_ a: [Character], _ b: [Character]) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
            }
            swap(&previous, &current)
        }
        return previous[b.count]
    }
}
