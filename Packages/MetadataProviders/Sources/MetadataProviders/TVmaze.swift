import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// TVmaze's public API: TV shows, seasons, episodes, cast and artwork, free
/// and without a key. The data is CC BY-SA 4.0 (Coreplay credits TVmaze in
/// Settings ▸ Metadata) and requests are limited to about 20 every 10
/// seconds, so lookups go one show at a time.
///
/// https://www.tvmaze.com/api
public struct TVmazeClient: Sendable {
    public enum Failure: LocalizedError, Equatable {
        case rateLimited
        case server(Int)
        case unreadableResponse

        public var errorDescription: String? {
            switch self {
            case .rateLimited: "TVmaze is busy. Coreplay will try again shortly."
            case .server(let status): "TVmaze returned an error (\(status))."
            case .unreadableResponse: "TVmaze sent something Coreplay couldn\u{2019}t read."
            }
        }
    }

    public static let baseURL = URL(string: "https://api.tvmaze.com/")!
    public static let userAgent = "Coreplay/0.3 (personal media player for iPhone, iPad and Mac)"

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// Shows whose names are like `title`, best first.
    public func searchShows(title: String) async throws -> [TVmazeShow] {
        let results: [TVmazeSearchResult] = try await get("search/shows", query: [URLQueryItem(name: "q", value: title)]) ?? []
        return results.map(\.show)
    }

    /// A show by its IMDb ID (from an `.nfo` file), or `nil` if TVmaze doesn't know it.
    public func show(imdbID: String) async throws -> TVmazeShow? {
        try await get("lookup/shows", query: [URLQueryItem(name: "imdb", value: imdbID)])
    }

    /// A show with every season, episode and the main cast.
    public func showDetails(id: Int) async throws -> TVmazeShowDetails? {
        try await get("shows/\(id)", query: [
            URLQueryItem(name: "embed[]", value: "episodes"),
            URLQueryItem(name: "embed[]", value: "seasons"),
            URLQueryItem(name: "embed[]", value: "cast"),
        ])
    }

    /// The show's posters, banners and backgrounds.
    public func images(showID: Int) async throws -> [TVmazeImage] {
        try await get("shows/\(showID)/images", query: []) ?? []
    }

    /// Downloads an image from TVmaze's image server.
    public func image(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 30
        let (data, response) = try await session.data(for: request)
        try Self.check(response)
        return data
    }

    func request(_ path: String, query: [URLQueryItem]) -> URLRequest {
        var components = URLComponents(url: Self.baseURL.appending(path: path), resolvingAgainstBaseURL: false)!
        components.queryItems = query.isEmpty ? nil : query
        var request = URLRequest(url: components.url!)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20
        return request
    }

    /// Decodes a response; `nil` for "not found".
    private func get<Value: Decodable>(_ path: String, query: [URLQueryItem]) async throws -> Value? {
        let request = request(path, query: query)
        var attempt = 0
        while true {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse {
                if http.statusCode == 429, attempt < 3 {
                    attempt += 1
                    try await Task.sleep(for: .seconds(Double(attempt) * 2))
                    continue
                }
                if http.statusCode == 404 {
                    return nil
                }
            }
            try Self.check(response)
            do {
                return try JSONDecoder().decode(Value.self, from: data)
            } catch {
                throw Failure.unreadableResponse
            }
        }
    }

    private static func check(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        switch http.statusCode {
        case 200..<300: return
        case 429: throw Failure.rateLimited
        default: throw Failure.server(http.statusCode)
        }
    }
}

// MARK: - Responses

struct TVmazeSearchResult: Decodable, Sendable {
    var show: TVmazeShow
}

/// An image in two sizes.
public struct TVmazeImageLinks: Decodable, Sendable, Equatable {
    public var medium: String?
    public var original: String?

    public init(medium: String? = nil, original: String? = nil) {
        self.medium = medium
        self.original = original
    }

    /// The biggest one.
    public var best: URL? {
        (original ?? medium).flatMap(URL.init(string:))
    }
}

public struct TVmazeShow: Decodable, Sendable, Equatable {
    public struct Rating: Decodable, Sendable, Equatable {
        public var average: Double?
    }

    public struct Network: Decodable, Sendable, Equatable {
        public var name: String
    }

    public struct Externals: Decodable, Sendable, Equatable {
        public var imdb: String?
        public var thetvdb: Int?
    }

    public var id: Int
    public var url: String?
    public var name: String
    public var language: String?
    public var genres: [String]?
    public var premiered: String?
    public var runtime: Int?
    public var averageRuntime: Int?
    public var rating: Rating?
    public var weight: Int?
    public var network: Network?
    public var webChannel: Network?
    public var externals: Externals?
    public var image: TVmazeImageLinks?
    /// HTML, e.g. "<p><b>Breaking Bad</b> follows…</p>".
    public var summary: String?

    public init(id: Int, name: String, premiered: String? = nil, weight: Int? = nil) {
        self.id = id
        self.name = name
        self.premiered = premiered
        self.weight = weight
    }

    public var year: Int? {
        guard let premiered, premiered.count >= 4 else { return nil }
        return Int(premiered.prefix(4))
    }

    public var plainSummary: String? {
        HTMLText.plain(summary)
    }
}

public struct TVmazeEpisode: Decodable, Sendable, Equatable {
    public var id: Int
    public var name: String?
    public var season: Int
    /// `nil` for specials.
    public var number: Int?
    public var airdate: String?
    public var runtime: Int?
    public var image: TVmazeImageLinks?
    public var summary: String?
}

public struct TVmazeSeason: Decodable, Sendable, Equatable {
    public var id: Int
    public var number: Int
    public var name: String?
    public var premiereDate: String?
    public var image: TVmazeImageLinks?
    public var summary: String?
}

public struct TVmazeCastCredit: Decodable, Sendable, Equatable {
    public struct Person: Decodable, Sendable, Equatable {
        public var name: String
        public var image: TVmazeImageLinks?
    }

    public struct Character: Decodable, Sendable, Equatable {
        public var name: String?
    }

    public var person: Person
    public var character: Character?
}

/// A show with its seasons, episodes and cast (`embed[]`).
public struct TVmazeShowDetails: Decodable, Sendable, Equatable {
    public struct Embedded: Decodable, Sendable, Equatable {
        public var episodes: [TVmazeEpisode]?
        public var seasons: [TVmazeSeason]?
        public var cast: [TVmazeCastCredit]?
    }

    public var show: TVmazeShow
    public var embedded: Embedded?

    private enum CodingKeys: String, CodingKey {
        case embedded = "_embedded"
    }

    public init(from decoder: any Decoder) throws {
        show = try TVmazeShow(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        embedded = try container.decodeIfPresent(Embedded.self, forKey: .embedded)
    }

    public var episodes: [TVmazeEpisode] { embedded?.episodes ?? [] }
    public var seasons: [TVmazeSeason] { embedded?.seasons ?? [] }
    public var cast: [TVmazeCastCredit] { embedded?.cast ?? [] }
}

/// An entry in a show's image gallery.
public struct TVmazeImage: Decodable, Sendable, Equatable {
    public struct Resolutions: Decodable, Sendable, Equatable {
        public struct Link: Decodable, Sendable, Equatable {
            public var url: String
            public var width: Int?
            public var height: Int?
        }

        public var original: Link?
        public var medium: Link?
    }

    public var id: Int
    /// "poster", "background", "banner", "typography".
    public var type: String?
    public var main: Bool?
    public var resolutions: Resolutions?

    /// The show's main background picture, for show pages.
    public static func background(in images: [TVmazeImage]) -> URL? {
        let backgrounds = images.filter { $0.type == "background" }
        let pick = backgrounds.first(where: { $0.main == true }) ?? backgrounds.first
        return (pick?.resolutions?.original?.url).flatMap(URL.init(string:))
    }
}

// MARK: - Matching

public enum TVmazeMatching {
    /// The search result that is really the show, by title and year, or `nil`.
    public static func bestShow(_ shows: [TVmazeShow], title: String, year: Int?) -> TVmazeShow? {
        let candidates = shows.map {
            TMDBMatching.Candidate(id: $0.id, titles: [$0.name], year: $0.year, votes: ($0.weight ?? 0) * 50)
        }
        guard let id = TMDBMatching.best(candidates, title: title, year: year) else { return nil }
        return shows.first { $0.id == id }
    }
}

// MARK: - HTML

/// Turns the bits of HTML TVmaze uses in summaries into plain text.
public enum HTMLText {
    public static func plain(_ html: String?) -> String? {
        guard var text = html, !text.isEmpty else { return nil }
        text = text.replacingOccurrences(of: "<br>", with: "\n", options: .caseInsensitive)
        text = text.replacingOccurrences(of: "<br/>", with: "\n", options: .caseInsensitive)
        text = text.replacingOccurrences(of: "<br />", with: "\n", options: .caseInsensitive)
        text = text.replacingOccurrences(of: "</p>", with: "\n\n", options: .caseInsensitive)
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        let entities = [
            "&amp;": "&", "&quot;": "\"", "&#39;": "\u{2019}", "&apos;": "\u{2019}",
            "&lt;": "<", "&gt;": ">", "&nbsp;": " ", "&hellip;": "\u{2026}",
            "&mdash;": "\u{2014}", "&ndash;": "\u{2013}", "&rsquo;": "\u{2019}", "&lsquo;": "\u{2018}",
            "&ldquo;": "\u{201C}", "&rdquo;": "\u{201D}",
        ]
        for (entity, replacement) in entities {
            text = text.replacingOccurrences(of: entity, with: replacement)
        }
        let lines = text
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        var paragraphs: [String] = []
        var current: [String] = []
        for line in lines {
            if line.isEmpty {
                if !current.isEmpty {
                    paragraphs.append(current.joined(separator: " "))
                    current = []
                }
            } else {
                current.append(line)
            }
        }
        if !current.isEmpty {
            paragraphs.append(current.joined(separator: " "))
        }
        let result = paragraphs.joined(separator: "\n\n")
        return result.isEmpty ? nil : result
    }
}
