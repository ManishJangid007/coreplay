import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// Details from a Kodi-style `.nfo` file: `<movie>`, `<tvshow>` or
/// `<episodedetails>`. Media managers (Kodi, Jellyfin, tinyMediaManager,
/// Radarr, Sonarr) write these next to the video, and they win over names
/// and online lookups because someone chose them on purpose.
///
/// An `.nfo` that is just a link (an IMDb or TMDB address) yields the IDs.
public struct NFOInfo: Sendable, Equatable {
    public enum Kind: String, Sendable {
        case movie
        case show
        case episode
    }

    public struct Person: Sendable, Equatable, Codable {
        public var name: String
        public var role: String?
        public var imageURL: String?

        public init(name: String, role: String? = nil, imageURL: String? = nil) {
            self.name = name
            self.role = role
            self.imageURL = imageURL
        }
    }

    public var kind: Kind?
    public var title: String?
    public var originalTitle: String?
    public var sortTitle: String?
    public var showTitle: String?
    public var year: Int?
    /// "1995-12-15" (`premiered`, `releasedate` or `aired`).
    public var releaseDate: String?
    public var overview: String?
    public var tagline: String?
    /// Minutes.
    public var runtime: Int?
    public var contentRating: String?
    public var genres: [String] = []
    public var directors: [String] = []
    public var studios: [String] = []
    public var cast: [Person] = []
    public var season: Int?
    public var episode: Int?
    public var tmdbID: Int?
    public var imdbID: String?
    public var tvdbID: Int?
    public var rating: Double?

    public init() {}

    /// Reads a file; `nil` when it isn't a readable `.nfo` at all.
    public static func read(url: URL) -> NFOInfo? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe), data.count < 4 * 1_024 * 1_024 else { return nil }
        return parse(data)
    }

    public static func parse(_ data: Data) -> NFOInfo? {
        if let info = NFOParser.parse(data), info.kind != nil {
            return info
        }
        // Not XML (or not one of Kodi's elements): look for links instead.
        let text = String(decoding: data, as: UTF8.self)
        var info = NFOInfo()
        info.imdbID = firstMatch(#"tt\d{7,9}"#, in: text)
        if let tmdb = firstMatch(#"themoviedb\.org/movie/\d+"#, in: text) {
            info.kind = .movie
            info.tmdbID = Int(tmdb.split(separator: "/").last ?? "")
        } else if let tmdb = firstMatch(#"themoviedb\.org/tv/\d+"#, in: text) {
            info.kind = .show
            info.tmdbID = Int(tmdb.split(separator: "/").last ?? "")
        }
        return info.imdbID != nil || info.tmdbID != nil ? info : nil
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range, in: text) else { return nil }
        return String(text[range])
    }
}

/// A small SAX reader for Kodi's elements. Unknown elements are ignored.
private final class NFOParser: NSObject, XMLParserDelegate {
    private var info = NFOInfo()
    private var path: [String] = []
    private var text = ""
    private var attributes: [[String: String]] = []
    private var person: NFOInfo.Person?

    static func parse(_ data: Data) -> NFOInfo? {
        let delegate = NFOParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldResolveExternalEntities = false
        // Some writers append a link after the XML; keep what was read.
        _ = parser.parse()
        return delegate.info.kind == nil ? nil : delegate.info
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        let name = elementName.lowercased()
        path.append(name)
        attributes.append(attributeDict)
        text = ""
        if path.count == 1 {
            switch name {
            case "movie": info.kind = .movie
            case "tvshow": info.kind = .show
            case "episodedetails": info.kind = .episode
            default: break
            }
        }
        if name == "actor", path.count == 2 {
            person = NFOInfo.Person(name: "")
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        text += String(decoding: CDATABlock, as: UTF8.self)
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let name = elementName.lowercased()
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let attributeDict = attributes.last ?? [:]
        defer {
            path.removeLast()
            attributes.removeLast()
            text = ""
        }
        guard info.kind != nil else { return }

        // <actor><name/><role/><thumb/></actor>
        if path.count == 3, path[1] == "actor", person != nil {
            switch name {
            case "name": person?.name = value
            case "role": person?.role = value.isEmpty ? nil : value
            case "thumb": person?.imageURL = value.isEmpty ? nil : value
            default: break
            }
            return
        }
        if name == "actor", path.count == 2, let finished = person {
            if !finished.name.isEmpty {
                info.cast.append(finished)
            }
            person = nil
            return
        }
        // <uniqueid type="tmdb">949</uniqueid>
        if name == "uniqueid", path.count == 2 {
            setID(type: attributeDict["type"]?.lowercased() ?? "", value: value)
            return
        }
        // <ratings><rating name="themoviedb"><value>7.9</value></rating></ratings>
        if name == "value", path.count == 4, path[1] == "ratings", info.rating == nil {
            info.rating = Double(value)
            return
        }
        guard path.count == 2, !value.isEmpty else { return }
        switch name {
        case "title": info.title = value
        case "originaltitle": info.originalTitle = value
        case "sorttitle": info.sortTitle = value
        case "showtitle": info.showTitle = value
        case "year": info.year = Int(value.prefix(4))
        case "premiered", "releasedate", "aired":
            info.releaseDate = info.releaseDate ?? value
            if info.year == nil { info.year = Int(value.prefix(4)) }
        case "plot": info.overview = value
        case "outline": info.overview = info.overview ?? value
        case "tagline": info.tagline = value
        case "runtime": info.runtime = Int(value.prefix(while: \.isNumber))
        case "mpaa", "certification":
            // "Rated R", "US:R", "R"
            let rating = value.replacingOccurrences(of: "Rated ", with: "")
            info.contentRating = rating.split(separator: ":").last.map(String.init) ?? rating
        case "genre": info.genres.append(contentsOf: Self.split(value))
        case "director": info.directors.append(contentsOf: Self.split(value))
        case "studio": info.studios.append(contentsOf: Self.split(value))
        case "season": info.season = Int(value)
        case "episode": info.episode = Int(value)
        case "rating": info.rating = info.rating ?? Double(value)
        case "id", "imdbid", "imdb_id":
            if value.hasPrefix("tt") { info.imdbID = value } else if name == "id" { setID(type: "tvdb", value: value) }
        case "tmdbid", "tmdb": info.tmdbID = Int(value)
        case "tvdbid": info.tvdbID = Int(value)
        default: break
        }
    }

    private func setID(type: String, value: String) {
        switch type {
        case "tmdb", "themoviedb": info.tmdbID = Int(value) ?? info.tmdbID
        case "imdb": info.imdbID = value.hasPrefix("tt") ? value : info.imdbID
        case "tvdb", "thetvdb": info.tvdbID = Int(value) ?? info.tvdbID
        default:
            if value.hasPrefix("tt") { info.imdbID = value }
        }
    }

    /// "Action / Crime" and "Action, Crime" both hold two values.
    private static func split(_ value: String) -> [String] {
        value.split(whereSeparator: { $0 == "/" || $0 == "," || $0 == "|" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
