import Foundation

/// Something the user asked to play: a local file, a file from a share, or a stream.
///
/// Items are plain values so they can move freely between the queue, the
/// router and the engines. The library (Milestone 3+) will build these from
/// its SwiftData models.
public struct PlaybackItem: Identifiable, Hashable, Sendable {
    /// What the item is expected to contain. Used for UI decisions before the
    /// engine has opened the media (the engine has the final word on video).
    public enum Kind: String, Hashable, Sendable, Codable {
        case audio
        case video
        case unknown
    }

    public let id: UUID
    public var url: URL
    public var kind: Kind
    public var title: String
    public var artist: String?
    public var albumTitle: String?
    public var artworkURL: URL?
    /// Position to start from, in seconds. `nil` starts at the beginning.
    public var startPosition: TimeInterval?
    public var enginePreference: EnginePreference
    /// Sidecar subtitle files to load with the media (e.g. `Movie.en.srt`).
    public var externalSubtitleURLs: [URL]
    /// `true` when `url` came from a document picker, "Open in…" or a
    /// security-scoped bookmark and needs `startAccessingSecurityScopedResource`.
    public var requiresSecurityScope: Bool
    /// The library's identifier for this file, when it was played from the
    /// library. Library items keep their (possibly user-edited) title, artist
    /// and artwork instead of whatever the engine reads from the file.
    public var libraryID: UUID?
    /// A short clip behind a title (the hero carousel's preview): no
    /// subtitles, no AirPlay, no Picture in Picture, and the screen may sleep.
    public var isPreview: Bool
    /// `false` opens no audio output at all, so a silent preview never
    /// interrupts music playing in another app.
    public var playsAudio: Bool
    /// The track's ReplayGain values, read from its tags just before it plays.
    public var replayGain: ReplayGainValues?
    /// Part of the file played as if it were the whole item: a cue sheet's
    /// track inside one long recording. The player's times count from its start.
    public var segment: PlaybackSegment?
    /// A DVD or Blu-ray (a folder copied from the disc, or an image), which
    /// VLC plays with its menus. `url` is then the folder holding VIDEO_TS or
    /// BDMV, or the image. The player sets this when it opens one.
    public var disc: DiscKind?
    /// The login for a file on a share, looked up in the Keychain by the
    /// player just before it opens the file and handed to VLC as options.
    public var credential: NetworkCredential?

    public init(
        id: UUID = UUID(),
        url: URL,
        kind: Kind? = nil,
        title: String? = nil,
        artist: String? = nil,
        albumTitle: String? = nil,
        artworkURL: URL? = nil,
        startPosition: TimeInterval? = nil,
        enginePreference: EnginePreference = .automatic,
        externalSubtitleURLs: [URL] = [],
        requiresSecurityScope: Bool = false,
        libraryID: UUID? = nil,
        isPreview: Bool = false,
        playsAudio: Bool = true
    ) {
        self.id = id
        self.url = url
        self.kind = kind ?? ContainerFormat(url: url).kindHint
        self.title = title ?? PlaybackItem.displayTitle(for: url)
        self.artist = artist
        self.albumTitle = albumTitle
        self.artworkURL = artworkURL
        self.startPosition = startPosition
        self.enginePreference = enginePreference
        self.externalSubtitleURLs = externalSubtitleURLs
        self.requiresSecurityScope = requiresSecurityScope
        self.libraryID = libraryID
        self.isPreview = isPreview
        self.playsAudio = playsAudio
    }

    /// A readable title derived from a URL, used until real metadata arrives.
    ///
    /// `The.Grand.Budapest.Hotel_2014.mkv` becomes `The Grand Budapest Hotel 2014`.
    /// Proper title parsing and matching arrive with the video library (Milestone 4).
    public static func displayTitle(for url: URL) -> String {
        let base: String
        if url.isFileURL {
            base = url.deletingPathExtension().lastPathComponent
        } else if !url.lastPathComponent.isEmpty, url.lastPathComponent != "/" {
            base = url.deletingPathExtension().lastPathComponent
        } else {
            // A bare stream address: the host name is the most readable thing we have.
            return url.host() ?? url.absoluteString
        }
        let separators = CharacterSet(charactersIn: "._")
        let words = base
            .components(separatedBy: separators)
            .flatMap { $0.split(separator: " ") }
            .map(String.init)
            .filter { !$0.isEmpty }
        let cleaned = words.joined(separator: " ")
        return cleaned.isEmpty ? base : cleaned
    }
}

/// Which engine should play an item.
public enum EnginePreference: String, Hashable, Sendable, Codable, CaseIterable {
    /// Let the router pick: AVFoundation when everything is natively supported, VLC otherwise.
    case automatic
    /// Always use VLC for this item.
    case vlc
    /// Always use AVFoundation for this item (may fail for formats Apple can't play).
    case avFoundation
}

/// A stretch of a file: from `start` to `end` (the end of the file when `nil`).
public struct PlaybackSegment: Hashable, Sendable {
    public var start: TimeInterval
    public var end: TimeInterval?

    public init(start: TimeInterval, end: TimeInterval? = nil) {
        self.start = max(0, start)
        self.end = end.map { max($0, start) }
    }

    /// Its length, given the whole file's.
    public func duration(fileDuration: TimeInterval?) -> TimeInterval? {
        guard let end = end ?? fileDuration else { return nil }
        return max(0, end - start)
    }

    /// `true` when `next` picks up exactly where this one stops, in the same file.
    public func continues(into next: PlaybackSegment) -> Bool {
        guard let end else { return false }
        return abs(next.start - end) < 0.05
    }
}

extension PlaylistEntry {
    /// The entry as something to play: a cue sheet's track becomes a segment of its file.
    public var playbackItem: PlaybackItem {
        var item = PlaybackItem(url: url, title: title, artist: artist)
        if let start, start > 0 || end != nil {
            item.segment = PlaybackSegment(start: start, end: end)
        }
        return item
    }
}
