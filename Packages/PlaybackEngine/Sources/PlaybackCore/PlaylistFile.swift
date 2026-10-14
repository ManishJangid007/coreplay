import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// One entry of a playlist file.
public struct PlaylistEntry: Hashable, Sendable {
    public var url: URL
    public var title: String?
    public var artist: String?
    /// The length the playlist gives, in seconds (it may be wrong).
    public var duration: TimeInterval?
    /// For a track of a cue sheet: where it starts in the file.
    public var start: TimeInterval?
    /// For a track of a cue sheet: where the next one starts (`nil`: the end of the file).
    public var end: TimeInterval?

    public init(url: URL, title: String? = nil, artist: String? = nil, duration: TimeInterval? = nil, start: TimeInterval? = nil, end: TimeInterval? = nil) {
        self.url = url
        self.title = title
        self.artist = artist
        self.duration = duration
        self.start = start
        self.end = end
    }
}

/// Reads the playlist files VLC opens: M3U and M3U8, PLS, XSPF, and cue
/// sheets (one audio file split into tracks). Relative paths are resolved
/// against the playlist's own folder, and Windows paths are understood.
public enum PlaylistFile {
    public enum Format: String, Hashable, Sendable, CaseIterable {
        case m3u
        case pls
        case xspf
        case cue
    }

    /// The format of a playlist file, from its extension. HLS streams
    /// (`.m3u8` over HTTP) are media, not playlists.
    public static func format(of url: URL) -> Format? {
        switch url.pathExtension.lowercased() {
        case "m3u":
            return .m3u
        case "m3u8":
            return url.isFileURL ? .m3u : nil
        case "pls":
            return .pls
        case "xspf":
            return .xspf
        case "cue":
            return .cue
        default:
            return nil
        }
    }

    /// The entries of the playlist at `url`.
    public static func entries(at url: URL) throws -> [PlaylistEntry] {
        guard let format = format(of: url) else { return [] }
        let data = try Data(contentsOf: url)
        return parse(data, format: format, playlistURL: url)
    }

    public static func parse(_ data: Data, format: Format, playlistURL: URL) -> [PlaylistEntry] {
        let folder = playlistURL.deletingLastPathComponent()
        switch format {
        case .m3u:
            return parseM3U(text(data), folder: folder)
        case .pls:
            return parsePLS(text(data), folder: folder)
        case .xspf:
            return XSPFReader(folder: folder).read(data)
        case .cue:
            return parseCue(text(data), folder: folder)
        }
    }

    // MARK: M3U

    static func parseM3U(_ text: String, folder: URL) -> [PlaylistEntry] {
        var entries: [PlaylistEntry] = []
        var pending: (duration: TimeInterval?, artist: String?, title: String?)?
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.hasPrefix("#") {
                if line.uppercased().hasPrefix("#EXTINF:") {
                    pending = extinf(String(line.dropFirst(8)))
                }
                continue
            }
            guard let url = resolve(line, folder: folder) else {
                pending = nil
                continue
            }
            entries.append(PlaylistEntry(url: url, title: pending?.title, artist: pending?.artist, duration: pending?.duration))
            pending = nil
        }
        return entries
    }

    /// `#EXTINF:215,Artist - Title` (attributes such as `tvg-name="…"` may
    /// come before the comma).
    static func extinf(_ value: String) -> (duration: TimeInterval?, artist: String?, title: String?) {
        guard let comma = value.firstIndex(of: ",") else {
            return (seconds(value), nil, nil)
        }
        let head = value[..<comma]
        let durationText = head.split(separator: " ").first.map(String.init) ?? ""
        let name = value[value.index(after: comma)...].trimmingCharacters(in: .whitespaces)
        if let separator = name.range(of: " - ") {
            let artist = name[..<separator.lowerBound].trimmingCharacters(in: .whitespaces)
            let title = name[separator.upperBound...].trimmingCharacters(in: .whitespaces)
            return (seconds(durationText), artist.isEmpty ? nil : artist, title.isEmpty ? nil : title)
        }
        return (seconds(durationText), nil, name.isEmpty ? nil : name)
    }

    // MARK: PLS

    static func parsePLS(_ text: String, folder: URL) -> [PlaylistEntry] {
        var files: [Int: String] = [:]
        var titles: [Int: String] = [:]
        var lengths: [Int: TimeInterval] = [:]
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard let equals = line.firstIndex(of: "=") else { continue }
            let key = line[..<equals].lowercased()
            let value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            for (prefix, assign) in [("file", 0), ("title", 1), ("length", 2)] where key.hasPrefix(prefix) {
                guard let number = Int(key.dropFirst(prefix.count)) else { continue }
                switch assign {
                case 0: files[number] = value
                case 1: titles[number] = value
                default: lengths[number] = seconds(value)
                }
            }
        }
        return files.keys.sorted().compactMap { number in
            guard let path = files[number], let url = resolve(path, folder: folder) else { return nil }
            return PlaylistEntry(url: url, title: titles[number].flatMap { $0.isEmpty ? nil : $0 }, duration: lengths[number])
        }
    }

    // MARK: Cue sheets

    static func parseCue(_ text: String, folder: URL) -> [PlaylistEntry] {
        struct Track {
            var file: URL
            var title: String?
            var performer: String?
            var start: TimeInterval?
        }
        var albumPerformer: String?
        var currentFile: URL?
        var tracks: [Track] = []
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            let command = line.split(separator: " ", maxSplits: 1).first.map { $0.uppercased() } ?? ""
            let argument = line.split(separator: " ", maxSplits: 1).dropFirst().first.map(String.init) ?? ""
            switch command {
            case "FILE":
                currentFile = quoted(argument).flatMap { resolve($0, folder: folder) }
            case "TRACK":
                guard let currentFile else { continue }
                tracks.append(Track(file: currentFile))
            case "TITLE":
                if tracks.isEmpty { continue }
                tracks[tracks.count - 1].title = quoted(argument)
            case "PERFORMER":
                if tracks.isEmpty {
                    albumPerformer = quoted(argument)
                } else {
                    tracks[tracks.count - 1].performer = quoted(argument)
                }
            case "INDEX":
                // INDEX 01 mm:ss:ff, 75 frames a second. 00 is the gap before.
                let parts = argument.split(separator: " ")
                guard parts.count == 2, parts[0] == "01", !tracks.isEmpty else { continue }
                tracks[tracks.count - 1].start = cueTime(String(parts[1]))
            default:
                continue
            }
        }
        return tracks.enumerated().map { index, track in
            let next = index + 1 < tracks.count ? tracks[index + 1] : nil
            let end = next?.file == track.file ? next?.start : nil
            var duration: TimeInterval?
            if let end, let start = track.start {
                duration = end - start
            }
            return PlaylistEntry(url: track.file, title: track.title, artist: track.performer ?? albumPerformer, duration: duration, start: track.start ?? 0, end: end)
        }
    }

    /// `mm:ss:ff`, with 75 frames a second.
    static func cueTime(_ text: String) -> TimeInterval? {
        let parts = text.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 3, parts[1] < 60, parts[2] < 75 else { return nil }
        return TimeInterval(parts[0] * 60 + parts[1]) + TimeInterval(parts[2]) / 75
    }

    private static func quoted(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("\""), let close = trimmed.dropFirst().firstIndex(of: "\"") {
            let value = String(trimmed[trimmed.index(after: trimmed.startIndex)..<close])
            return value.isEmpty ? nil : value
        }
        // Unquoted: up to the first space (FILE name.wav WAVE).
        let value = trimmed.split(separator: " ").first.map(String.init)
        return value?.isEmpty == false ? value : nil
    }

    // MARK: Shared

    /// UTF-8 (with or without a byte-order mark), else Windows Latin 1.
    static func text(_ data: Data) -> String {
        var bytes = data
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) {
            bytes = bytes.dropFirst(3)
        }
        return String(data: bytes, encoding: .utf8) ?? String(data: bytes, encoding: .windowsCP1252) ?? String(decoding: bytes, as: UTF8.self)
    }

    /// An entry's location: a URL with a scheme, an absolute path, or a path
    /// relative to the playlist (Windows backslashes allowed).
    static func resolve(_ location: String, folder: URL) -> URL? {
        let trimmed = location.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if let scheme = trimmed.range(of: "://"), trimmed[..<scheme.lowerBound].allSatisfy({ $0.isLetter || $0 == "+" || $0 == "-" || $0 == "." }),
           trimmed.distance(from: trimmed.startIndex, to: scheme.lowerBound) > 1 {
            return URL(string: trimmed) ?? URL(string: trimmed.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) ?? trimmed)
        }
        var path = trimmed.replacingOccurrences(of: "\\", with: "/")
        // "C:/Music/…": a Windows drive can't be found here; keep the name only.
        if path.count > 2, path.dropFirst().hasPrefix(":/") {
            path = String(path.dropFirst(3))
            return folder.appending(path: (path as NSString).lastPathComponent)
        }
        if path.hasPrefix("/") {
            return URL(filePath: path)
        }
        return folder.appending(path: path).standardizedFileURL
    }

    /// "215", "215.5", "-1" (unknown).
    private static func seconds(_ text: String) -> TimeInterval? {
        guard let value = Double(text.trimmingCharacters(in: .whitespaces)), value > 0, value.isFinite else { return nil }
        return value
    }
}

/// XSPF: `<track>` elements with `<location>`, `<title>`, `<creator>` and
/// `<duration>` (milliseconds).
private final class XSPFReader: NSObject, XMLParserDelegate {
    private let folder: URL
    private var entries: [PlaylistEntry] = []
    private var current: [String: String]?
    private var text = ""

    init(folder: URL) {
        self.folder = folder
    }

    func read(_ data: Data) -> [PlaylistEntry] {
        let parser = XMLParser(data: data)
        parser.delegate = self
        _ = parser.parse()
        return entries
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        if elementName == "track" {
            current = [:]
        }
        text = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        text = ""
        guard current != nil else { return }
        switch elementName {
        case "location", "title", "creator", "duration":
            if current?[elementName] == nil, !value.isEmpty {
                current?[elementName] = value
            }
        case "track":
            if let fields = current, let location = fields["location"], let url = resolve(location) {
                let milliseconds = fields["duration"].flatMap(Double.init)
                entries.append(PlaylistEntry(
                    url: url,
                    title: fields["title"],
                    artist: fields["creator"],
                    duration: milliseconds.map { $0 / 1_000 }
                ))
            }
            current = nil
        default:
            break
        }
    }

    /// Locations are URIs: `file:///…`, `http://…`, or relative and percent-encoded.
    private func resolve(_ location: String) -> URL? {
        if location.contains("://") {
            return URL(string: location) ?? PlaylistFile.resolve(location, folder: folder)
        }
        let decoded = location.removingPercentEncoding ?? location
        return PlaylistFile.resolve(decoded, folder: folder)
    }
}
