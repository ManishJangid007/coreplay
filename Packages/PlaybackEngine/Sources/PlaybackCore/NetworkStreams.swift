import Foundation

/// Addresses for Open Network Stream: reading what someone pasted, and
/// naming the kind of stream it is.
public enum StreamAddress {
    public enum Kind: String, Hashable, Sendable {
        case hls, dash, http, rtsp, rtmp, rtp, udp, mms, srt, share

        public var title: String {
            switch self {
            case .hls: "HLS"
            case .dash: "MPEG-DASH"
            case .http: "HTTP"
            case .rtsp: "RTSP"
            case .rtmp: "RTMP"
            case .rtp: "RTP"
            case .udp: "UDP"
            case .mms: "MMS"
            case .srt: "SRT"
            case .share: "Network share"
            }
        }
    }

    /// Schemes VLC or AVFoundation open as streams (shares too).
    public static let schemes: Set<String> = [
        "http", "https", "rtsp", "rtsps", "rtmp", "rtmps", "rtmpe", "rtmpt",
        "rtp", "udp", "mms", "mmsh", "mmst", "srt",
        "smb", "ftp", "sftp", "nfs", "upnp",
    ]

    /// What someone pasted, as a URL to open: trimmed, "http://" added to a
    /// bare address ("example.com/live.m3u8"), and `nil` for anything that
    /// isn't a stream (local paths, other schemes, words).
    public static func url(from text: String) -> URL? {
        var text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for (open, close) in [("<", ">"), ("\"", "\""), ("'", "'")] where text.hasPrefix(open) && text.hasSuffix(close) && text.count > 1 {
            text = String(text.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
        }
        guard !text.isEmpty, !text.contains(where: \.isNewline) else { return nil }
        if let range = text.range(of: "://") {
            let scheme = text[..<range.lowerBound].lowercased()
            guard schemes.contains(scheme) else { return nil }
        } else {
            // A bare address needs a dot or a port to be a server: "localhost:8080/live", "example.com".
            let host = text.prefix { $0 != "/" && $0 != "?" }
            guard !host.contains(" "), host.contains(".") || host.contains(":"), !text.hasPrefix("/") else { return nil }
            text = "http://" + text
        }
        let url = URL(string: text)
            ?? text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.union(["#"])).flatMap { URL(string: $0) }
        guard let url, let scheme = url.scheme?.lowercased(), schemes.contains(scheme) else { return nil }
        // udp://@:1234 and rtp://@239.0.0.1:5004 listen without a host.
        if url.host(percentEncoded: false)?.isEmpty ?? true, !["udp", "rtp"].contains(scheme) {
            return nil
        }
        return url
    }

    public static func kind(of url: URL) -> Kind {
        let scheme = url.scheme?.lowercased() ?? ""
        if NetworkProtocol(scheme: scheme) != nil { return .share }
        switch scheme {
        case "rtsp", "rtsps": return .rtsp
        case "rtmp", "rtmps", "rtmpe", "rtmpt": return .rtmp
        case "rtp": return .rtp
        case "udp": return .udp
        case "mms", "mmsh", "mmst": return .mms
        case "srt": return .srt
        default:
            switch url.pathExtension.lowercased() {
            case "m3u8": return .hls
            case "mpd": return .dash
            default: return .http
            }
        }
    }

    /// A short title for a stream with no name: "live.m3u8 on example.com".
    public static func title(for url: URL) -> String {
        let host = url.host(percentEncoded: false) ?? ""
        let file = url.lastPathComponent
        if !file.isEmpty, file != "/" {
            return host.isEmpty ? file : "\(file) on \(host)"
        }
        return host.isEmpty ? url.absoluteString : host
    }
}

/// Streams opened before, newest first, as Open Network Stream lists them.
public struct RecentStreams: Codable, Hashable, Sendable {
    public struct Entry: Codable, Hashable, Sendable, Identifiable {
        public var url: URL
        public var lastOpened: Date
        public var id: URL { url }

        public init(url: URL, lastOpened: Date = .now) {
            self.url = url
            self.lastOpened = lastOpened
        }
    }

    public private(set) var entries: [Entry] = []
    public static let limit = 20

    public init(entries: [Entry] = []) {
        self.entries = Array(entries.prefix(Self.limit))
    }

    /// Puts a stream at the top. Addresses with a password are never kept.
    public mutating func add(_ url: URL, at date: Date = .now) {
        guard url.password == nil else { return }
        entries.removeAll { $0.url == url }
        entries.insert(Entry(url: url, lastOpened: date), at: 0)
        if entries.count > Self.limit {
            entries.removeLast(entries.count - Self.limit)
        }
    }

    public mutating func remove(_ url: URL) {
        entries.removeAll { $0.url == url }
    }

    public mutating func removeAll() {
        entries.removeAll()
    }
}
