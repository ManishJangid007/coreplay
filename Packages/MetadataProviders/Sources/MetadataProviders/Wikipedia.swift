import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Movie details from Wikipedia and Wikidata, free and without a key: the
/// article's poster, the opening of the article as a synopsis, and the IMDb
/// ID (so a TMDB key added later finds the same film at once).
///
/// Text is CC BY-SA 4.0 (Coreplay credits Wikipedia in Settings ▸
/// Metadata). Film posters on Wikipedia are usually non-free images kept at
/// a small size, so they're lower resolution than TMDB's.
public struct WikipediaClient: Sendable {
    public enum Failure: LocalizedError, Equatable {
        case server(Int)
        case unreadableResponse

        public var errorDescription: String? {
            switch self {
            case .server(let status): "Wikipedia returned an error (\(status))."
            case .unreadableResponse: "Wikipedia sent something Coreplay couldn\u{2019}t read."
            }
        }
    }

    public static let apiURL = URL(string: "https://en.wikipedia.org/w/api.php")!
    public static let wikidataURL = URL(string: "https://www.wikidata.org/w/api.php")!
    /// Wikimedia asks every client to name itself.
    public static let userAgent = "Coreplay/0.3 (personal media player for iPhone, iPad and Mac)"

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// Articles that might be the film, with their posters and openings, best first.
    public func searchFilms(title: String, year: Int?) async throws -> [WikipediaPage] {
        let search = [title, year.map(String.init), "film"].compactMap { $0 }.joined(separator: " ")
        let response: WikipediaQueryResponse = try await get(Self.apiURL, query: Self.pageQuery + [
            URLQueryItem(name: "generator", value: "search"),
            URLQueryItem(name: "gsrsearch", value: search),
            URLQueryItem(name: "gsrnamespace", value: "0"),
            URLQueryItem(name: "gsrlimit", value: "8"),
        ])
        return (response.query?.pages ?? []).sorted { ($0.index ?? .max) < ($1.index ?? .max) }
    }

    /// One article, for Fix Match.
    public func page(id: Int) async throws -> WikipediaPage? {
        let response: WikipediaQueryResponse = try await get(Self.apiURL, query: Self.pageQuery + [
            URLQueryItem(name: "pageids", value: String(id)),
        ])
        return response.query?.pages.first(where: { $0.missing != true })
    }

    /// The film's IMDb ID from Wikidata (property P345).
    public func imdbID(wikidataID: String) async throws -> String? {
        let response: WikidataClaimsResponse = try await get(Self.wikidataURL, query: [
            URLQueryItem(name: "action", value: "wbgetclaims"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "entity", value: wikidataID),
            URLQueryItem(name: "property", value: "P345"),
        ])
        return response.claims["P345"]?.lazy.compactMap(\.mainsnak.datavalue?.value).first { $0.hasPrefix("tt") }
    }

    /// Downloads an image from Wikimedia's image servers.
    public func image(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 30
        let (data, response) = try await session.data(for: request)
        try Self.check(response)
        return data
    }

    /// Everything one request can tell about each page: lead image (non-free
    /// images included, which is where film posters are), short description,
    /// plain-text opening and Wikidata item.
    static let pageQuery: [URLQueryItem] = [
        URLQueryItem(name: "action", value: "query"),
        URLQueryItem(name: "format", value: "json"),
        URLQueryItem(name: "formatversion", value: "2"),
        URLQueryItem(name: "redirects", value: "1"),
        URLQueryItem(name: "prop", value: "pageimages|description|extracts|pageprops"),
        URLQueryItem(name: "piprop", value: "thumbnail|original"),
        URLQueryItem(name: "pithumbsize", value: "780"),
        URLQueryItem(name: "pilicense", value: "any"),
        URLQueryItem(name: "exintro", value: "1"),
        URLQueryItem(name: "explaintext", value: "1"),
        URLQueryItem(name: "exsentences", value: "5"),
        URLQueryItem(name: "exlimit", value: "max"),
        URLQueryItem(name: "ppprop", value: "wikibase_item|disambiguation"),
    ]

    func request(_ base: URL, query: [URLQueryItem]) -> URLRequest {
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        components.queryItems = query
        var request = URLRequest(url: components.url!)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20
        return request
    }

    private func get<Value: Decodable>(_ base: URL, query: [URLQueryItem]) async throws -> Value {
        let (data, response) = try await session.data(for: request(base, query: query))
        try Self.check(response)
        do {
            return try JSONDecoder().decode(Value.self, from: data)
        } catch {
            throw Failure.unreadableResponse
        }
    }

    private static func check(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else { throw Failure.server(http.statusCode) }
    }
}

// MARK: - Responses

struct WikipediaQueryResponse: Decodable {
    struct Query: Decodable {
        var pages: [WikipediaPage]
    }

    var query: Query?
}

/// A Wikipedia article, as the query API describes it.
public struct WikipediaPage: Decodable, Sendable, Equatable {
    public struct Image: Decodable, Sendable, Equatable {
        public var source: String
        public var width: Int?
        public var height: Int?

        public init(source: String, width: Int? = nil, height: Int? = nil) {
            self.source = source
            self.width = width
            self.height = height
        }
    }

    public struct PageProps: Decodable, Sendable, Equatable {
        public var wikibaseItem: String?
        public var disambiguation: String?

        private enum CodingKeys: String, CodingKey {
            case wikibaseItem = "wikibase_item"
            case disambiguation
        }

        public init(wikibaseItem: String? = nil, disambiguation: String? = nil) {
            self.wikibaseItem = wikibaseItem
            self.disambiguation = disambiguation
        }
    }

    public var pageid: Int
    public var title: String
    /// Search rank, from 1.
    public var index: Int?
    public var missing: Bool?
    /// Short description, e.g. "1995 film by Michael Mann".
    public var description: String?
    /// The article's opening, as plain text.
    public var extract: String?
    public var thumbnail: Image?
    public var original: Image?
    public var pageprops: PageProps?

    public init(pageid: Int, title: String, index: Int? = nil, description: String? = nil, extract: String? = nil, thumbnail: Image? = nil, original: Image? = nil, pageprops: PageProps? = nil) {
        self.pageid = pageid
        self.title = title
        self.index = index
        self.description = description
        self.extract = extract
        self.thumbnail = thumbnail
        self.original = original
        self.pageprops = pageprops
    }

    /// The largest version of the lead image.
    public var posterURL: URL? {
        let candidates = [original, thumbnail].compactMap { $0 }
        let best = candidates.max { ($0.width ?? 0) < ($1.width ?? 0) }
        return best.flatMap { URL(string: $0.source) }
    }

    /// The article on the web, for credits.
    public var url: URL? {
        let path = title.replacingOccurrences(of: " ", with: "_")
        return URL(string: "https://en.wikipedia.org/wiki/")?.appending(path: path)
    }
}

struct WikidataClaimsResponse: Decodable {
    struct Claim: Decodable {
        struct Snak: Decodable {
            struct DataValue: Decodable {
                var value: String?

                init(from decoder: any Decoder) throws {
                    // Values can be strings or objects; only strings matter here.
                    let container = try decoder.container(keyedBy: CodingKeys.self)
                    value = try? container.decode(String.self, forKey: .value)
                }

                private enum CodingKeys: String, CodingKey {
                    case value
                }
            }

            var datavalue: DataValue?
        }

        var mainsnak: Snak
    }

    var claims: [String: [Claim]]
}

// MARK: - Matching

/// Picks the article that is the film: a film (by its title or description),
/// with a close title and, when the file names a year, the same year (±1).
public enum WikipediaFilms {
    /// "Heat (1995 film)" → title "Heat", year 1995, marked as a film.
    public static func parseTitle(_ pageTitle: String) -> (title: String, year: Int?, saysFilm: Bool) {
        guard let open = pageTitle.lastIndex(of: "("), pageTitle.hasSuffix(")") else {
            return (pageTitle, nil, false)
        }
        let base = pageTitle[..<open].trimmingCharacters(in: .whitespaces)
        let qualifier = pageTitle[pageTitle.index(after: open)..<pageTitle.index(before: pageTitle.endIndex)].lowercased()
        let saysFilm = qualifier.contains("film") || qualifier.contains("movie")
        return (base, firstYear(in: qualifier), saysFilm)
    }

    /// The film's year from its title, description or opening sentence.
    public static func year(of page: WikipediaPage) -> Int? {
        if let year = parseTitle(page.title).year { return year }
        if let description = page.description, let year = firstYear(in: description) { return year }
        if let extract = page.extract {
            let opening = extract.prefix(240)
            if let range = opening.range(of: #"\b(is|was) an? [^.]{0,40}?\b(1[89]\d{2}|20\d{2})\b"#, options: .regularExpression) {
                return firstYear(in: String(opening[range]))
            }
        }
        return nil
    }

    /// Whether the article is about a single film (not a series, a
    /// soundtrack, a book or a person).
    public static func isFilm(_ page: WikipediaPage) -> Bool {
        if page.pageprops?.disambiguation != nil || page.missing == true { return false }
        if parseTitle(page.title).saysFilm { return true }
        let description = page.description?.lowercased() ?? ""
        if description.contains("film") || description.contains("movie") {
            let notAFilm = ["film series", "film franchise", "film director", "film producer", "film score", "film actor", "film actress", "film critic", "film studio", "film festival", "soundtrack"]
            return !notAFilm.contains(where: { description.contains($0) })
        }
        if !description.isEmpty {
            // Described, but as something else.
            return false
        }
        guard let opening = page.extract?.prefix(200).lowercased() else { return false }
        return opening.range(of: #"\b(is|was) an? [^.]{0,60}?\bfilm\b"#, options: .regularExpression) != nil
    }

    /// The best article for a film called `title` (from `year`), or `nil`.
    public static func best(_ pages: [WikipediaPage], title: String, year: Int?) -> WikipediaPage? {
        let films = pages.filter(isFilm)
        let candidates = films.map { page in
            TMDBMatching.Candidate(
                id: page.pageid,
                titles: [parseTitle(page.title).title],
                year: self.year(of: page),
                votes: max(0, 10 - (page.index ?? 10)) * 100
            )
        }
        guard let id = TMDBMatching.best(candidates, title: title, year: year) else { return nil }
        return films.first { $0.pageid == id }
    }

    /// A clean synopsis: the opening without pronunciation guides.
    public static func synopsis(_ page: WikipediaPage) -> String? {
        guard var text = page.extract?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        text = text.replacingOccurrences(of: #"\s*\([^()]*(pronounced|/)[^()]*\)"#, with: "", options: .regularExpression)
        return text
    }

    static func firstYear(in text: String) -> Int? {
        guard let range = text.range(of: #"\b(1[89]\d{2}|20\d{2})\b"#, options: .regularExpression) else { return nil }
        return Int(text[range])
    }
}
