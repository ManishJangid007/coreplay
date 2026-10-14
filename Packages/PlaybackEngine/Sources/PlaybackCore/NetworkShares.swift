import Foundation

// Network shares: what they are, how to address them, and what's in their
// folders. VLC does the talking (PlaybackEngine's NetworkBrowser); these
// are plain values so they can be tested anywhere.

/// The kinds of share Coreplay browses and plays from, all through VLC.
public enum NetworkProtocol: String, CaseIterable, Codable, Hashable, Sendable, Identifiable {
    /// Windows, Mac and NAS shares: SMB 2 and 3, and SMB 1 when a server
    /// only speaks that (VLC's smb2 and dsm modules).
    case smb
    case ftp
    case sftp
    case nfs
    /// Media servers (DLNA): found on the network, never typed in.
    case upnp

    public var id: String { rawValue }

    /// The URL scheme VLC opens.
    public var scheme: String { rawValue }

    public init?(scheme: String?) {
        switch scheme?.lowercased() {
        case "smb", "cifs": self = .smb
        case "ftp": self = .ftp
        case "sftp": self = .sftp
        case "nfs": self = .nfs
        case "upnp": self = .upnp
        default: return nil
        }
    }

    public var title: String {
        switch self {
        case .smb: "SMB"
        case .ftp: "FTP"
        case .sftp: "SFTP"
        case .nfs: "NFS"
        case .upnp: "UPnP"
        }
    }

    /// A line under the protocol in Connect to Server.
    public var detail: String {
        switch self {
        case .smb: "Shared folders on Macs, Windows PCs and NAS drives"
        case .ftp: "FTP servers"
        case .sftp: "Servers you reach with SSH"
        case .nfs: "Unix and NAS exports"
        case .upnp: "Media servers such as Plex, Jellyfin and NAS drives"
        }
    }

    public var defaultPort: Int? {
        switch self {
        case .smb: 445
        case .ftp: 21
        case .sftp: 22
        case .nfs: 2049
        case .upnp: nil
        }
    }

    public var systemImage: String {
        switch self {
        case .smb: "externaldrive.connected.to.line.below"
        case .ftp, .sftp: "server.rack"
        case .nfs: "externaldrive.badge.wifi"
        case .upnp: "tv.and.mediabox"
        }
    }

    /// Whether servers usually ask for a user name and password.
    public var usesLogin: Bool {
        switch self {
        case .smb, .ftp, .sftp: true
        case .nfs, .upnp: false
        }
    }

    /// SMB has Windows domains (or workgroups).
    public var usesDomain: Bool { self == .smb }

    /// The ones you can type an address for (UPnP servers are only found).
    public static let connectable: [NetworkProtocol] = [.smb, .sftp, .ftp, .nfs]
}

/// A user name and password for a share. Kept in the Keychain by the app,
/// handed to VLC as per-item options, never written into a URL.
public struct NetworkCredential: Hashable, Sendable, Codable {
    public var user: String
    public var password: String
    /// Windows domain or workgroup (SMB only).
    public var domain: String?

    public init(user: String, password: String, domain: String? = nil) {
        self.user = user
        self.password = password
        let domain = domain?.trimmingCharacters(in: .whitespaces)
        self.domain = domain?.isEmpty == false ? domain : nil
    }

    /// libVLC options that log in with this credential for `url`'s protocol.
    /// (VLC's own option names: `smb-user`, `ftp-pwd`, `sftp-user`…)
    public func vlcOptions(for url: URL) -> [String] {
        switch NetworkProtocol(scheme: url.scheme) {
        case .smb:
            var options = [":smb-user=\(user)", ":smb-pwd=\(password)"]
            if let domain {
                options.append(":smb-domain=\(domain)")
            }
            return options
        case .ftp:
            return [":ftp-user=\(user)", ":ftp-pwd=\(password)"]
        case .sftp:
            return [":sftp-user=\(user)", ":sftp-pwd=\(password)"]
        case .nfs, .upnp, nil:
            return []
        }
    }
}

/// Addresses of shares: building, reading what someone typed, and showing them.
public enum NetworkAddress {
    /// What Connect to Server understood from an address.
    public struct Parsed: Hashable, Sendable {
        public var networkProtocol: NetworkProtocol
        public var host: String
        public var port: Int?
        /// Starts with "/", or is empty for the server itself.
        public var path: String
        public var user: String?

        public var url: URL? {
            NetworkAddress.url(protocol: networkProtocol, host: host, port: port, path: path)
        }
    }

    /// `smb://nas.local/Movies/`: no user or password, path percent-encoded,
    /// a trailing slash because it's a folder. `nil` for an empty host.
    public static func url(protocol networkProtocol: NetworkProtocol, host: String, port: Int? = nil, path: String = "") -> URL? {
        let host = host.trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty, !host.contains(where: { $0.isWhitespace || $0 == "/" }) else { return nil }
        var components = URLComponents()
        components.scheme = networkProtocol.scheme
        // IPv6 addresses go in brackets.
        components.percentEncodedHost = host.contains(":") && !host.hasPrefix("[") ? "[\(host)]" : host
        if let port, port != networkProtocol.defaultPort {
            components.port = port
        }
        var folder = path.trimmingCharacters(in: .whitespaces)
        if !folder.isEmpty, !folder.hasPrefix("/") {
            folder = "/" + folder
        }
        if !folder.hasSuffix("/") {
            folder += "/"
        }
        components.path = folder
        return components.url
    }

    /// Reads an address typed into Connect to Server: "smb://nas.local/Movies",
    /// "nas.local/Movies" (using `defaultProtocol`), "bob@192.168.1.5",
    /// "ftp://[fe80::1]:2121/pub". `nil` when there's no server in it.
    public static func parse(_ text: String, defaultProtocol: NetworkProtocol) -> Parsed? {
        var text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Windows-style \\server\share.
        if text.hasPrefix("\\\\") {
            text = "smb://" + text.dropFirst(2).replacingOccurrences(of: "\\", with: "/")
        }
        guard !text.isEmpty else { return nil }
        let networkProtocol: NetworkProtocol
        if let range = text.range(of: "://") {
            guard let parsed = NetworkProtocol(scheme: String(text[..<range.lowerBound])) else { return nil }
            networkProtocol = parsed
        } else {
            networkProtocol = defaultProtocol
            text = "\(defaultProtocol.scheme)://" + text
        }
        guard let components = URLComponents(string: text) ?? URLComponents(string: text.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) ?? ""),
              var host = components.host, !host.isEmpty else { return nil }
        if host.hasPrefix("["), host.hasSuffix("]") {
            host = String(host.dropFirst().dropLast())
        }
        let user = components.user?.removingPercentEncoding
        return Parsed(
            networkProtocol: networkProtocol,
            host: host,
            port: components.port,
            path: components.path == "/" ? "" : components.path,
            user: user?.isEmpty == false ? user : nil
        )
    }

    /// The URL without a user name or password in it.
    public static func withoutLogin(_ url: URL) -> URL {
        guard url.user != nil || url.password != nil,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        components.user = nil
        components.password = nil
        return components.url ?? url
    }

    /// Whether VLC browses this URL as a share (rather than playing a stream).
    public static func isShare(_ url: URL) -> Bool {
        NetworkProtocol(scheme: url.scheme) != nil
    }

    /// The server's part: "nas.local" or "nas.local:2121".
    public static func server(of url: URL) -> String {
        let host = url.host(percentEncoded: false) ?? ""
        if let port = url.port, port != NetworkProtocol(scheme: url.scheme)?.defaultPort {
            return "\(host):\(port)"
        }
        return host
    }

    /// A folder's name: its last path component, or the server for the top.
    public static func name(of url: URL) -> String {
        let components = url.pathComponents.filter { $0 != "/" }
        return components.last ?? server(of: url)
    }

    /// "nas.local › Movies › 2024", for showing where a folder is.
    public static func displayPath(_ url: URL) -> String {
        ([server(of: url)] + url.pathComponents.filter { $0 != "/" }).joined(separator: " \u{203A} ")
    }

    /// A child of a folder URL. Folders keep a trailing slash.
    public static func child(named name: String, of folder: URL, isFolder: Bool) -> URL {
        folder.appending(path: name, directoryHint: isFolder ? .isDirectory : .notDirectory)
    }
}

/// One thing in a network folder.
public struct NetworkEntry: Identifiable, Hashable, Sendable {
    public enum Kind: String, Hashable, Sendable {
        case folder, video, audio, subtitle, playlist, image, other
    }

    public var id: URL { url }
    public var name: String
    public var url: URL
    public var kind: Kind
    /// In bytes, when the server says.
    public var size: Int64?
    public var modified: Date?

    public init(name: String, url: URL, isFolder: Bool, size: Int64? = nil, modified: Date? = nil) {
        self.name = name
        self.url = url
        self.kind = isFolder ? .folder : Self.kind(forName: name)
        self.size = isFolder ? nil : size
        self.modified = modified
    }

    public var isFolder: Bool { kind == .folder }
    public var isPlayable: Bool { kind == .video || kind == .audio }

    public static let subtitleExtensions: Set<String> = ["srt", "ass", "ssa", "vtt", "sub", "idx", "smi", "sup", "ttml", "dfxp"]
    static let playlistExtensions: Set<String> = ["m3u", "m3u8", "pls", "xspf", "cue"]
    static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "gif", "heic", "webp", "bmp", "tiff"]

    public static func kind(forName name: String) -> Kind {
        let ext = (name as NSString).pathExtension.lowercased()
        if subtitleExtensions.contains(ext) { return .subtitle }
        // An HLS playlist is a stream (video), the rest are lists of files.
        if ext != "m3u8", playlistExtensions.contains(ext) { return .playlist }
        if imageExtensions.contains(ext) { return .image }
        switch ContainerFormat(fileExtension: ext).kindHint {
        case .video: return .video
        case .audio: return .audio
        case .unknown: return .other
        }
    }

    /// Dot files, macOS's "._" companions and NAS housekeeping folders.
    public static func isHidden(name: String) -> Bool {
        if name.hasPrefix(".") { return true }
        return ["@eaDir", "#recycle", "$RECYCLE.BIN", "System Volume Information", "Thumbs.db", "desktop.ini", "lost+found"]
            .contains { $0.caseInsensitiveCompare(name) == .orderedSame }
    }

    /// Folders first, then by name as the Finder sorts ("Episode 2" before "Episode 10").
    public static func sorted(_ entries: [NetworkEntry]) -> [NetworkEntry] {
        entries.sorted { lhs, rhs in
            if lhs.isFolder != rhs.isFolder { return lhs.isFolder }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    /// Subtitle files beside a video with its name: "Film.srt", "Film.en.srt"
    /// for "Film.mkv".
    public static func subtitles(for video: NetworkEntry, in entries: [NetworkEntry]) -> [URL] {
        let base = (video.name as NSString).deletingPathExtension.lowercased()
        guard !base.isEmpty else { return [] }
        return entries
            .filter { entry in
                guard entry.kind == .subtitle else { return false }
                let name = (entry.name as NSString).deletingPathExtension.lowercased()
                return name == base || name.hasPrefix(base + ".")
            }
            .map(\.url)
    }
}
