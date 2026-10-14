import Foundation
import MetadataProviders
import PlaybackCore
import Security
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Your OpenSubtitles.com API key and (optionally) account, kept in the
/// Keychain, never in preferences and never synced.
public struct OpenSubtitlesCredentials: Hashable, Sendable {
    public var apiKey: String
    public var username: String
    public var password: String

    public init(apiKey: String, username: String = "", password: String = "") {
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.username = username.trimmingCharacters(in: .whitespacesAndNewlines)
        self.password = password
    }

    public var hasAccount: Bool {
        !username.isEmpty && !password.isEmpty
    }

    private static let service = "Coreplay OpenSubtitles"

    /// The saved credentials, or `nil` when there's no API key.
    public static func load() -> OpenSubtitlesCredentials? {
        guard let apiKey = KeychainValue.load(service: service, account: "api-key"), !apiKey.isEmpty else { return nil }
        return OpenSubtitlesCredentials(
            apiKey: apiKey,
            username: KeychainValue.load(service: service, account: "username") ?? "",
            password: KeychainValue.load(service: service, account: "password") ?? ""
        )
    }

    public func save() throws {
        try KeychainValue.save(apiKey, service: Self.service, account: "api-key")
        if hasAccount {
            try KeychainValue.save(username, service: Self.service, account: "username")
            try KeychainValue.save(password, service: Self.service, account: "password")
        } else {
            KeychainValue.delete(service: Self.service, account: "username")
            KeychainValue.delete(service: Self.service, account: "password")
        }
    }

    public static func delete() {
        for account in ["api-key", "username", "password"] {
            KeychainValue.delete(service: service, account: account)
        }
    }
}

/// Finds subtitles on OpenSubtitles.com for what's playing and downloads
/// them into Caches, where the player loads them like any subtitle file.
public actor OpenSubtitlesProvider: OnlineSubtitleProvider {
    public nonisolated let name = "OpenSubtitles"

    private let client: OpenSubtitlesClient
    private let credentials: OpenSubtitlesCredentials
    /// From signing in; downloads count against the account's daily quota.
    private var token: String?

    public init(credentials: OpenSubtitlesCredentials, session: URLSession = .shared) {
        self.credentials = credentials
        self.client = OpenSubtitlesClient(apiKey: credentials.apiKey, session: session)
    }

    /// The provider for the saved credentials, if a key is saved.
    public static func saved() -> OpenSubtitlesProvider? {
        OpenSubtitlesCredentials.load().map { OpenSubtitlesProvider(credentials: $0) }
    }

    public func search(_ request: SubtitleSearchRequest) async throws -> [OnlineSubtitle] {
        var hash: String?
        if let url = request.fileURL, url.isFileURL {
            let isScoped = url.startAccessingSecurityScopedResource()
            defer {
                if isScoped { url.stopAccessingSecurityScopedResource() }
            }
            hash = try? OpenSubtitlesClient.hash(ofFileAt: url)
        }
        let isEpisode = request.season != nil || request.episode != nil
        let query = OpenSubtitlesClient.Query(
            movieHash: hash,
            title: request.title,
            imdbID: isEpisode ? nil : request.imdbID,
            parentIMDbID: isEpisode ? request.showIMDbID : nil,
            season: request.season,
            episode: request.episode,
            languages: request.languages.map(Self.openSubtitlesLanguage)
        )
        return try await client.search(query).map { subtitle in
            OnlineSubtitle(
                id: subtitle.id,
                language: subtitle.language,
                release: subtitle.release,
                downloadCount: subtitle.downloadCount,
                isHearingImpaired: subtitle.isHearingImpaired,
                isForeignPartsOnly: subtitle.isForeignPartsOnly,
                isMachineTranslated: subtitle.isMachineTranslated,
                matchesFile: subtitle.matchesFile
            )
        }
    }

    public func download(_ subtitle: OnlineSubtitle) async throws -> URL {
        if token == nil, credentials.hasAccount {
            token = try await client.signIn(username: credentials.username, password: credentials.password)
        }
        let (data, fileName) = try await client.download(fileID: subtitle.id, token: token)
        let folder = try FileManager.default
            .url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appending(path: "Coreplay/Subtitles", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let safeName = fileName.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        let url = folder.appending(path: "\(subtitle.id)-\(safeName)")
        try data.write(to: url, options: .atomic)
        return url
    }

    /// OpenSubtitles writes Portuguese and Chinese with their region.
    static func openSubtitlesLanguage(_ code: String) -> String {
        switch MediaTrack.normalizedLanguageCode(code) {
        case "pt": code.lowercased().contains("br") ? "pt-br" : "pt-pt"
        case "zh": code.lowercased().contains("tw") || code.lowercased().contains("hant") ? "zh-tw" : "zh-cn"
        case let other: other
        }
    }
}

extension LibraryManager {
    /// What a subtitle search should look for: the library's title, year,
    /// IMDb IDs and episode numbers when it knows the video.
    public func subtitleSearchRequest(for item: PlaybackItem) -> SubtitleSearchRequest {
        var request = SubtitleSearchRequest(fileURL: item.url, title: item.title)
        guard let libraryID = item.libraryID, let video = mediaFile(id: libraryID)?.video else { return request }
        if video.kind == .episode {
            request.title = video.showTitle ?? video.show?.title ?? video.title
            request.showIMDbID = video.show?.imdbID
            request.season = video.seasonNumber
            request.episode = video.episodeNumber
        } else {
            request.title = video.title
            request.year = video.year
            request.imdbID = video.imdbID
        }
        return request
    }
}

/// One string in the Keychain.
enum KeychainValue {
    static func load(service: String, account: String) -> String? {
        var query = baseQuery(service: service, account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ value: String, service: String, account: String) throws {
        let query = baseQuery(service: service, account: account)
        let data = Data(value.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            #if os(iOS)
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            #endif
            let added = SecItemAdd(item as CFDictionary, nil)
            guard added == errSecSuccess else { throw MetadataKeyStore.KeychainError(status: added) }
        } else if status != errSecSuccess {
            throw MetadataKeyStore.KeychainError(status: status)
        }
    }

    static func delete(service: String, account: String) {
        SecItemDelete(baseQuery(service: service, account: account) as CFDictionary)
    }

    private static func baseQuery(service: String, account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
