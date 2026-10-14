import Foundation

/// Which audio and subtitle tracks a video starts with (Settings ▸ Playback
/// ▸ Languages), when you haven't chosen for that file before.
public struct TrackPreferences: Hashable, Sendable, Codable {
    public enum Subtitles: String, Hashable, Sendable, Codable, CaseIterable, Identifiable {
        /// Whatever the file says (often off, sometimes forced subtitles).
        case automatic
        /// When the audio isn't in your subtitle language; otherwise only
        /// forced subtitles (signs, other languages spoken on screen).
        case foreignAudio
        case always
        case off

        public var id: Self { self }

        public var title: String {
            switch self {
            case .automatic: "Automatic"
            case .foreignAudio: "When the Audio Is in Another Language"
            case .always: "Always"
            case .off: "Off"
            }
        }
    }

    /// What to change once the tracks are known.
    public enum Choice: Hashable, Sendable {
        case keep
        case off
        case track(MediaTrack.ID)
    }

    /// An ISO 639 code; `nil` keeps the file's own default audio.
    public var audioLanguage: String?
    public var subtitles: Subtitles
    /// An ISO 639 code; `nil` uses the app's language.
    public var subtitleLanguage: String?

    public init(audioLanguage: String? = nil, subtitles: Subtitles = .automatic, subtitleLanguage: String? = nil) {
        self.audioLanguage = audioLanguage
        self.subtitles = subtitles
        self.subtitleLanguage = subtitleLanguage
    }

    public static let automatic = TrackPreferences()

    /// The audio track to start with.
    public func audioChoice(from tracks: [MediaTrack]) -> Choice {
        guard let audioLanguage else { return .keep }
        let matching = tracks.filter { MediaTrack.languagesMatch($0.languageCode, audioLanguage) }
        guard !matching.isEmpty else { return .keep }
        if matching.contains(where: \.isSelected) { return .keep }
        // The main track before commentaries and audio description.
        let main = matching.first { !Self.isSecondaryAudio($0) } ?? matching[0]
        return .track(main.id)
    }

    /// The subtitles to start with, given the audio that will play.
    /// - Parameter appLanguage: The language the app runs in, for when no
    ///   subtitle language is chosen.
    public func subtitleChoice(from tracks: [MediaTrack], audio: MediaTrack?, appLanguage: String) -> Choice {
        let language = subtitleLanguage ?? appLanguage
        let inLanguage = tracks.filter { MediaTrack.languagesMatch($0.languageCode, language) }
        let full = inLanguage.filter { !$0.isForced }
        let forced = inLanguage.filter(\.isForced)
        // Plain subtitles before ones for the deaf and hard of hearing.
        let bestFull = full.first { !$0.isSDH } ?? full.first
        switch subtitles {
        case .automatic:
            return .keep
        case .off:
            return tracks.contains(where: \.isSelected) ? .off : .keep
        case .always:
            guard let bestFull else { return .keep }
            return bestFull.isSelected ? .keep : .track(bestFull.id)
        case .foreignAudio:
            let audioIsUnderstood = MediaTrack.languagesMatch(audio?.languageCode, language)
            if audioIsUnderstood || audio?.languageCode == nil {
                // Only what's needed: forced lines for signs and other languages.
                if let forcedTrack = forced.first {
                    return forcedTrack.isSelected ? .keep : .track(forcedTrack.id)
                }
                return tracks.contains(where: \.isSelected) ? .off : .keep
            }
            guard let bestFull else { return .keep }
            return bestFull.isSelected ? .keep : .track(bestFull.id)
        }
    }

    /// Commentary and audio description tracks are never the main one.
    static func isSecondaryAudio(_ track: MediaTrack) -> Bool {
        let name = track.name.lowercased()
        return name.contains("commentary") || name.contains("description") || name.contains("descriptive")
    }

    /// Languages offered in Settings, the app's own first.
    public static func commonLanguages(first preferred: [String]) -> [String] {
        var codes: [String] = []
        for code in preferred.map(MediaTrack.normalizedLanguageCode) + common where !codes.contains(code) {
            codes.append(code)
        }
        return codes
    }

    static let common = [
        "en", "es", "fr", "de", "it", "pt", "nl", "sv", "no", "da", "fi", "pl", "cs", "hu", "ro", "el", "tr",
        "ru", "uk", "ar", "he", "hi", "bn", "ta", "te", "th", "vi", "id", "ms", "zh", "ja", "ko",
    ]
}

/// What you chose for one file, so it plays the same way next time: its
/// tracks, timing and picture options.
public struct FileOptions: Hashable, Sendable, Codable {
    public var audioLanguage: String?
    public var subtitleLanguage: String?
    public var subtitlesOff: Bool
    public var audioDelay: TimeInterval
    public var subtitleDelay: TimeInterval
    public var aspectRatio: VideoRatio?
    public var cropRatio: VideoRatio?
    public var transform: VideoTransform
    public var deinterlace: DeinterlaceMode

    public init(
        audioLanguage: String? = nil,
        subtitleLanguage: String? = nil,
        subtitlesOff: Bool = false,
        audioDelay: TimeInterval = 0,
        subtitleDelay: TimeInterval = 0,
        aspectRatio: VideoRatio? = nil,
        cropRatio: VideoRatio? = nil,
        transform: VideoTransform = .identity,
        deinterlace: DeinterlaceMode = .automatic
    ) {
        self.audioLanguage = audioLanguage
        self.subtitleLanguage = subtitleLanguage
        self.subtitlesOff = subtitlesOff
        self.audioDelay = audioDelay
        self.subtitleDelay = subtitleDelay
        self.aspectRatio = aspectRatio
        self.cropRatio = cropRatio
        self.transform = transform
        self.deinterlace = deinterlace
    }

    /// Nothing chosen: no need to remember the file.
    public var isEmpty: Bool {
        self == FileOptions()
    }

    /// Something only VLC does, so the file should open with VLC.
    public var needsVLC: Bool {
        audioDelay != 0 || subtitleDelay != 0 || aspectRatio != nil || cropRatio != nil || deinterlace != .automatic
    }

    /// Whether any track was chosen.
    public var choosesTracks: Bool {
        audioLanguage != nil || subtitleLanguage != nil || subtitlesOff
    }
}

/// Remembered options for the files played most recently, oldest dropped
/// first. A plain value, so the app can save it however it likes.
public struct FileOptionsStore: Hashable, Sendable, Codable {
    public static let capacity = 500

    private var entries: [String: FileOptions] = [:]
    /// Keys, least recently used first.
    private var order: [String] = []

    public init() {}

    public var count: Int { entries.count }

    /// A stable key for an item: the library's identifier, or the file's path.
    public static func key(for item: PlaybackItem) -> String {
        if let libraryID = item.libraryID {
            return "library:\(libraryID.uuidString)"
        }
        if item.url.isFileURL {
            return "file:\(item.url.standardizedFileURL.path(percentEncoded: false))"
        }
        return "url:\(item.url.absoluteString)"
    }

    public func options(for key: String) -> FileOptions? {
        entries[key]
    }

    /// Remembers `options` for `key` (or forgets the file when nothing's chosen).
    public mutating func set(_ options: FileOptions, for key: String) {
        order.removeAll { $0 == key }
        guard !options.isEmpty else {
            entries[key] = nil
            return
        }
        entries[key] = options
        order.append(key)
        while order.count > Self.capacity {
            entries[order.removeFirst()] = nil
        }
    }
}
