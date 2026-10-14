import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// OpenSubtitles.com's REST API: subtitles for a video, found by the file's
/// hash (an exact match for that release) or by its title, and downloaded
/// as a file the player loads like any other.
///
/// It needs your own API key (opensubtitles.com ▸ API consumers), and
/// downloads count against an account's daily quota, so you sign in too.
/// Only the file's hash, its title and the languages you ask for are sent.
///
/// https://opensubtitles.stoplight.io/docs/opensubtitles-api
public struct OpenSubtitlesClient: Sendable {
    public enum Failure: LocalizedError, Equatable {
        /// The API key or the account was refused.
        case notAuthorized
        /// Today's downloads are used up.
        case quotaExceeded(resetTime: String?)
        case rateLimited
        case server(Int)
        case unreadableResponse

        public var errorDescription: String? {
            switch self {
            case .notAuthorized:
                "OpenSubtitles didn\u{2019}t accept the API key or the account. Check them in Settings \u{25B8} Subtitles."
            case .quotaExceeded(let reset):
                "You\u{2019}ve used today\u{2019}s OpenSubtitles downloads\(reset.map { ". They reset in \($0)" } ?? "")."
            case .rateLimited:
                "OpenSubtitles is busy. Try again in a moment."
            case .server(let status):
                "OpenSubtitles returned an error (\(status))."
            case .unreadableResponse:
                "OpenSubtitles sent something Coreplay couldn\u{2019}t read."
            }
        }
    }

    public static let baseURL = URL(string: "https://api.opensubtitles.com/api/v1/")!
    public static let userAgent = "Coreplay v0.6"

    private let apiKey: String
    private let session: URLSession

    public init(apiKey: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }

    // MARK: Searching

    /// What to look for. The hash finds subtitles made for this exact file;
    /// the title (with season and episode for TV) finds the rest.
    public struct Query: Hashable, Sendable {
        public var movieHash: String?
        public var title: String?
        public var imdbID: String?
        /// For an episode: its show's IMDb ID.
        public var parentIMDbID: String?
        public var season: Int?
        public var episode: Int?
        /// ISO 639-1 codes ("en", "pt-br").
        public var languages: [String]

        public init(movieHash: String? = nil, title: String? = nil, imdbID: String? = nil, parentIMDbID: String? = nil, season: Int? = nil, episode: Int? = nil, languages: [String] = []) {
            self.movieHash = movieHash
            self.title = title
            self.imdbID = imdbID
            self.parentIMDbID = parentIMDbID
            self.season = season
            self.episode = episode
            self.languages = languages
        }

        var queryItems: [URLQueryItem] {
            // The API wants its parameters in alphabetical order, lower case.
            var items: [URLQueryItem] = []
            if let episode { items.append(URLQueryItem(name: "episode_number", value: String(episode))) }
            if let number = Self.imdbNumber(imdbID) { items.append(URLQueryItem(name: "imdb_id", value: String(number))) }
            let codes = languages.map { $0.lowercased() }.filter { !$0.isEmpty }
            if !codes.isEmpty { items.append(URLQueryItem(name: "languages", value: codes.sorted().joined(separator: ","))) }
            if let movieHash { items.append(URLQueryItem(name: "moviehash", value: movieHash.lowercased())) }
            if let number = Self.imdbNumber(parentIMDbID) { items.append(URLQueryItem(name: "parent_imdb_id", value: String(number))) }
            if let title, !title.isEmpty { items.append(URLQueryItem(name: "query", value: title.lowercased())) }
            if let season { items.append(URLQueryItem(name: "season_number", value: String(season))) }
            return items
        }

        /// "tt0113277" → 113277.
        private static func imdbNumber(_ id: String?) -> Int? {
            guard let id else { return nil }
            return Int(id.lowercased().replacingOccurrences(of: "tt", with: ""))
        }
    }

    /// One subtitle file on offer.
    public struct Subtitle: Hashable, Sendable, Identifiable {
        /// The file's ID, used to download it.
        public var id: Int
        public var language: String
        /// The release it was made for ("Movie.2019.1080p.BluRay.x264").
        public var release: String
        public var fileName: String?
        public var downloadCount: Int
        public var isHearingImpaired: Bool
        /// Only the lines in other languages (signs, foreign dialogue).
        public var isForeignPartsOnly: Bool
        public var isMachineTranslated: Bool
        public var isFromTrustedUploader: Bool
        /// Made for this exact file (its hash matched).
        public var matchesFile: Bool
    }

    /// Subtitles for `query`, best first: exact file matches, then trusted
    /// uploaders, then the most downloaded.
    public func search(_ query: Query) async throws -> [Subtitle] {
        var components = URLComponents(url: Self.baseURL.appending(path: "subtitles"), resolvingAgainstBaseURL: false)!
        components.queryItems = query.queryItems
        let request = request(url: components.url!, method: "GET", token: nil, body: nil)
        let response: SearchResponse = try await send(request)
        return Self.subtitles(from: response)
    }

    static func subtitles(from response: SearchResponse) -> [Subtitle] {
        var result: [Subtitle] = []
        for entry in response.data {
            let attributes = entry.attributes
            for file in attributes.files {
                result.append(Subtitle(
                    id: file.fileID,
                    language: attributes.language ?? "",
                    release: attributes.release ?? file.fileName ?? "",
                    fileName: file.fileName,
                    downloadCount: attributes.downloadCount ?? 0,
                    isHearingImpaired: attributes.hearingImpaired ?? false,
                    isForeignPartsOnly: attributes.foreignPartsOnly ?? false,
                    isMachineTranslated: (attributes.machineTranslated ?? false) || (attributes.aiTranslated ?? false),
                    isFromTrustedUploader: attributes.fromTrusted ?? false,
                    matchesFile: attributes.moviehashMatch ?? false
                ))
            }
        }
        return result.sorted { lhs, rhs in
            if lhs.matchesFile != rhs.matchesFile { return lhs.matchesFile }
            if lhs.isMachineTranslated != rhs.isMachineTranslated { return !lhs.isMachineTranslated }
            if lhs.isForeignPartsOnly != rhs.isForeignPartsOnly { return !lhs.isForeignPartsOnly }
            if lhs.isFromTrustedUploader != rhs.isFromTrustedUploader { return lhs.isFromTrustedUploader }
            return lhs.downloadCount > rhs.downloadCount
        }
    }

    // MARK: Signing in and downloading

    /// Signs in to an OpenSubtitles account; the token goes with downloads.
    public func signIn(username: String, password: String) async throws -> String {
        let body = try JSONEncoder().encode(["username": username, "password": password])
        let request = request(url: Self.baseURL.appending(path: "login"), method: "POST", token: nil, body: body)
        let response: LoginResponse = try await send(request)
        return response.token
    }

    /// A subtitle file's contents, with its name.
    public func download(fileID: Int, token: String?) async throws -> (data: Data, fileName: String) {
        let body = try JSONEncoder().encode(["file_id": fileID])
        let request = request(url: Self.baseURL.appending(path: "download"), method: "POST", token: token, body: body)
        let response: DownloadResponse = try await send(request)
        guard let link = URL(string: response.link) else { throw Failure.unreadableResponse }
        var fileRequest = URLRequest(url: link)
        fileRequest.timeoutInterval = 30
        let (data, fileResponse) = try await session.data(for: fileRequest)
        try Self.check(fileResponse, data: data)
        return (data, response.fileName ?? "subtitles-\(fileID).srt")
    }

    // MARK: Requests

    func request(url: URL, method: String, token: String?, body: Data?) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(apiKey, forHTTPHeaderField: "Api-Key")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }
        request.timeoutInterval = 20
        return request
    }

    private func send<Value: Decodable>(_ request: URLRequest) async throws -> Value {
        let (data, response) = try await session.data(for: request)
        try Self.check(response, data: data)
        do {
            return try JSONDecoder().decode(Value.self, from: data)
        } catch {
            throw Failure.unreadableResponse
        }
    }

    static func check(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        switch http.statusCode {
        case 200..<300:
            return
        case 401, 403:
            throw Failure.notAuthorized
        case 406:
            // Download quota used up; the body says when it resets.
            let quota = try? JSONDecoder().decode(DownloadResponse.Quota.self, from: data)
            throw Failure.quotaExceeded(resetTime: quota?.resetTime)
        case 429:
            throw Failure.rateLimited
        default:
            throw Failure.server(http.statusCode)
        }
    }

    // MARK: The file hash

    /// OpenSubtitles' hash: the file's size plus the 64-bit little-endian
    /// words of its first and last 64 KB, wrapping, as 16 hex digits.
    public static func hash(ofFileAt url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let size = try handle.seekToEnd()
        // 64 KB from each end (all of it, twice, for smaller files).
        let chunk = min(UInt64(65_536), size)
        try handle.seek(toOffset: 0)
        let head = try handle.read(upToCount: Int(chunk)) ?? Data()
        try handle.seek(toOffset: size - chunk)
        let tail = try handle.read(upToCount: Int(chunk)) ?? Data()
        return hash(size: size, head: head, tail: tail)
    }

    static func hash(size: UInt64, head: Data, tail: Data) -> String {
        var value = size
        for block in [head, tail] {
            let bytes = [UInt8](block)
            var index = 0
            while index + 8 <= bytes.count {
                var word: UInt64 = 0
                for byte in 0..<8 {
                    word |= UInt64(bytes[index + byte]) << (8 * UInt64(byte))
                }
                value &+= word
                index += 8
            }
        }
        let hex = String(value, radix: 16)
        return String(repeating: "0", count: max(0, 16 - hex.count)) + hex
    }
}

// MARK: - Responses

struct SearchResponse: Decodable, Sendable {
    struct Entry: Decodable, Sendable {
        var attributes: Attributes
    }

    struct Attributes: Decodable, Sendable {
        var language: String?
        var downloadCount: Int?
        var hearingImpaired: Bool?
        var foreignPartsOnly: Bool?
        var machineTranslated: Bool?
        var aiTranslated: Bool?
        var fromTrusted: Bool?
        var moviehashMatch: Bool?
        var release: String?
        var files: [File]

        enum CodingKeys: String, CodingKey {
            case language, release, files
            case downloadCount = "download_count"
            case hearingImpaired = "hearing_impaired"
            case foreignPartsOnly = "foreign_parts_only"
            case machineTranslated = "machine_translated"
            case aiTranslated = "ai_translated"
            case fromTrusted = "from_trusted"
            case moviehashMatch = "moviehash_match"
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            language = try? container.decode(String.self, forKey: .language)
            downloadCount = try? container.decode(Int.self, forKey: .downloadCount)
            hearingImpaired = try? container.decode(Bool.self, forKey: .hearingImpaired)
            foreignPartsOnly = try? container.decode(Bool.self, forKey: .foreignPartsOnly)
            machineTranslated = try? container.decode(Bool.self, forKey: .machineTranslated)
            aiTranslated = try? container.decode(Bool.self, forKey: .aiTranslated)
            fromTrusted = try? container.decode(Bool.self, forKey: .fromTrusted)
            moviehashMatch = try? container.decode(Bool.self, forKey: .moviehashMatch)
            release = try? container.decode(String.self, forKey: .release)
            files = (try? container.decode([File].self, forKey: .files)) ?? []
        }
    }

    struct File: Decodable, Sendable {
        var fileID: Int
        var fileName: String?

        enum CodingKeys: String, CodingKey {
            case fileID = "file_id"
            case fileName = "file_name"
        }
    }

    var data: [Entry]
}

struct LoginResponse: Decodable, Sendable {
    var token: String
}

struct DownloadResponse: Decodable, Sendable {
    struct Quota: Decodable, Sendable {
        var resetTime: String?

        enum CodingKeys: String, CodingKey {
            case resetTime = "reset_time"
        }
    }

    var link: String
    var fileName: String?
    var remaining: Int?

    enum CodingKeys: String, CodingKey {
        case link, remaining
        case fileName = "file_name"
    }
}
