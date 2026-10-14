import Foundation
import Observation
import PlaybackCore

/// A server you connected to and kept, shown under Sources.
public struct SavedServer: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    /// What you call it; the host when empty.
    public var name: String
    public var networkProtocol: NetworkProtocol
    public var host: String
    public var port: Int?
    /// The folder it opens at ("" for the server itself).
    public var path: String
    /// The login's user name (the password is in the Keychain).
    public var user: String?
    /// Windows domain or workgroup (SMB).
    public var domain: String?

    public init(
        id: UUID = UUID(),
        name: String = "",
        networkProtocol: NetworkProtocol,
        host: String,
        port: Int? = nil,
        path: String = "",
        user: String? = nil,
        domain: String? = nil
    ) {
        self.id = id
        self.name = name
        self.networkProtocol = networkProtocol
        self.host = host
        self.port = port
        self.path = path
        self.user = user?.isEmpty == false ? user : nil
        self.domain = domain?.isEmpty == false ? domain : nil
    }

    /// Where it opens, without the login.
    public var url: URL? {
        NetworkAddress.url(protocol: networkProtocol, host: host, port: port, path: path)
    }

    public var displayName: String {
        let name = name.trimmingCharacters(in: .whitespaces)
        if !name.isEmpty { return name }
        let folder = path.split(separator: "/").last.map(String.init)
        return folder ?? host
    }

    /// "SMB · nas.local/Movies".
    public var summary: String {
        let place = host + (port.map { ":\($0)" } ?? "") + (path.isEmpty ? "" : (path.hasPrefix("/") ? path : "/" + path))
        return "\(networkProtocol.title) \u{00B7} \(place)"
    }

    /// Whether `url` is on this server (same protocol, host and port).
    public func contains(_ url: URL) -> Bool {
        guard NetworkProtocol(scheme: url.scheme) == networkProtocol,
              url.host(percentEncoded: false)?.caseInsensitiveCompare(host) == .orderedSame else { return false }
        let defaultPort = networkProtocol.defaultPort
        return (url.port ?? defaultPort) == (port ?? defaultPort)
    }
}

/// Saved servers, recent streams and where network videos were left,
/// kept in a small file in Application Support. Passwords are never here:
/// they're in the Keychain (`NetworkKeychain`).
@MainActor
@Observable
public final class NetworkStore {
    public static let shared = NetworkStore()

    public private(set) var servers: [SavedServer] = []
    public private(set) var recentStreams = RecentStreams()

    /// A network video's place, by its address without a login.
    struct ResumePoint: Codable, Hashable {
        var position: TimeInterval
        var date: Date
    }

    @ObservationIgnored private var resumePoints: [String: ResumePoint] = [:]
    @ObservationIgnored private let fileURL: URL?
    /// The most network videos whose place is kept.
    static let resumeLimit = 300

    private struct Contents: Codable {
        var servers: [SavedServer] = []
        var recentStreams = RecentStreams()
        var resumePoints: [String: ResumePoint] = [:]
    }

    /// - Parameter fileURL: Where to keep everything; `nil` keeps it in memory (tests).
    public init(fileURL: URL? = NetworkStore.defaultFileURL) {
        self.fileURL = fileURL
        guard let fileURL, let data = try? Data(contentsOf: fileURL),
              let contents = try? JSONDecoder().decode(Contents.self, from: data) else { return }
        servers = contents.servers
        recentStreams = contents.recentStreams
        resumePoints = contents.resumePoints
    }

    public nonisolated static var defaultFileURL: URL? {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return support.appending(path: "Coreplay/Network.json")
    }

    // MARK: Servers

    /// Adds a server, or updates the one with the same id.
    public func save(_ server: SavedServer) {
        if let index = servers.firstIndex(where: { $0.id == server.id }) {
            servers[index] = server
        } else {
            servers.append(server)
        }
        servers.sort { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
        persist()
    }

    public func remove(_ server: SavedServer) {
        servers.removeAll { $0.id == server.id }
        persist()
    }

    /// The saved server `url` is on, if any (the one with the longest matching folder).
    public func server(for url: URL) -> SavedServer? {
        let path = url.path(percentEncoded: false)
        return servers
            .filter { $0.contains(url) }
            .max { lhs, rhs in
                let left = path.hasPrefix(lhs.path) ? lhs.path.count : -1
                let right = path.hasPrefix(rhs.path) ? rhs.path.count : -1
                return left < right
            }
    }

    // MARK: Streams

    public func noteStream(_ url: URL) {
        recentStreams.add(url)
        persist()
    }

    public func forgetStream(_ url: URL) {
        recentStreams.remove(url)
        persist()
    }

    public func forgetAllStreams() {
        recentStreams.removeAll()
        persist()
    }

    // MARK: Where network videos got to

    /// Where a network video was left, if it wasn't finished.
    public func resumePosition(for url: URL) -> TimeInterval? {
        resumePoints[Self.key(for: url)]?.position
    }

    /// Keeps a video's place, or forgets it (`nil`: finished or near the start).
    public func setResumePosition(_ position: TimeInterval?, for url: URL) {
        let key = Self.key(for: url)
        if let position, position > 0 {
            resumePoints[key] = ResumePoint(position: position, date: .now)
            if resumePoints.count > Self.resumeLimit {
                let oldest = resumePoints.sorted { $0.value.date < $1.value.date }.prefix(resumePoints.count - Self.resumeLimit)
                for (key, _) in oldest {
                    resumePoints[key] = nil
                }
            }
        } else if resumePoints[key] != nil {
            resumePoints[key] = nil
        } else {
            return
        }
        persist()
    }

    static func key(for url: URL) -> String {
        NetworkAddress.withoutLogin(url).absoluteString
    }

    private func persist() {
        guard let fileURL else { return }
        let contents = Contents(servers: servers, recentStreams: recentStreams, resumePoints: resumePoints)
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(contents).write(to: fileURL, options: .atomic)
        } catch {
            // Nothing to lose but convenience; the next change tries again.
        }
    }
}
