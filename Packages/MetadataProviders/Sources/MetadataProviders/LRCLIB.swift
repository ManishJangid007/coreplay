import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// LRCLIB (lrclib.net): free, keyless synced lyrics, looked up by title,
/// artist, album and length. Used only when lyrics lookup is turned on.
public struct LRCLIBClient: Sendable {
    public struct Result: Decodable, Hashable, Sendable {
        public let syncedLyrics: String?
        public let plainLyrics: String?
        public let instrumental: Bool?

        /// Synced words when there are some, otherwise plain.
        public var bestText: String? {
            if let synced = syncedLyrics, !synced.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return synced }
            if let plain = plainLyrics, !plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return plain }
            return nil
        }
    }

    public enum Failure: LocalizedError, Equatable {
        case server(Int)
        case unreadableResponse

        public var errorDescription: String? {
            switch self {
            case .server(let status): "LRCLIB returned an error (\(status))."
            case .unreadableResponse: "LRCLIB sent something Coreplay couldn\u{2019}t read."
            }
        }
    }

    public static let baseURL = URL(string: "https://lrclib.net/api/")!
    public static let userAgent = "Coreplay/0.8 (personal media player for iPhone, iPad and Mac)"

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// The song's lyrics, or `nil` when LRCLIB doesn't have them.
    public func lyrics(title: String, artist: String, album: String?, duration: TimeInterval?) async throws -> Result? {
        let (data, response) = try await session.data(for: Self.request(title: title, artist: artist, album: album, duration: duration))
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 404 { return nil }
            guard (200..<300).contains(http.statusCode) else { throw Failure.server(http.statusCode) }
        }
        return try Self.decode(data)
    }

    static func request(title: String, artist: String, album: String?, duration: TimeInterval?) -> URLRequest {
        var components = URLComponents(url: baseURL.appending(path: "get"), resolvingAgainstBaseURL: false)!
        var query = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist),
        ]
        if let album, !album.isEmpty {
            query.append(URLQueryItem(name: "album_name", value: album))
        }
        if let duration, duration > 0 {
            query.append(URLQueryItem(name: "duration", value: String(Int(duration.rounded()))))
        }
        components.queryItems = query
        var request = URLRequest(url: components.url!)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(userAgent, forHTTPHeaderField: "Lrclib-Client")
        request.timeoutInterval = 15
        return request
    }

    static func decode(_ data: Data) throws -> Result {
        do {
            return try JSONDecoder().decode(Result.self, from: data)
        } catch {
            throw Failure.unreadableResponse
        }
    }
}
