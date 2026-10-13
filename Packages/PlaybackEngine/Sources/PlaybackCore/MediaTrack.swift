import Foundation

/// An audio, video or subtitle track inside the playing media.
public struct MediaTrack: Identifiable, Hashable, Sendable {
    public enum Kind: String, Hashable, Sendable {
        case audio
        case video
        case subtitle
    }

    /// Engine-specific identifier. Only meaningful to the engine that produced it.
    public let id: String
    public var kind: Kind
    /// Name reported by the engine, e.g. "Track 2 - [English]" or "Commentary".
    public var name: String
    /// BCP-47 / ISO-639 code such as "en", "eng" or "pt-BR".
    public var languageCode: String?
    /// Human-readable codec, e.g. "AAC" or "A52 Audio (aka AC3)".
    public var codec: String?
    public var isSelected: Bool
    public var channelCount: Int?
    public var isExternal: Bool
    public var isForced: Bool
    /// Subtitles for the deaf and hard of hearing (or closed captions).
    public var isSDH: Bool

    public init(
        id: String,
        kind: Kind,
        name: String,
        languageCode: String? = nil,
        codec: String? = nil,
        isSelected: Bool = false,
        channelCount: Int? = nil,
        isExternal: Bool = false,
        isForced: Bool? = nil,
        isSDH: Bool? = nil
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.languageCode = languageCode
        self.codec = codec
        self.isSelected = isSelected
        self.channelCount = channelCount
        self.isExternal = isExternal
        let lowered = name.lowercased()
        self.isForced = isForced ?? lowered.contains("forced")
        self.isSDH = isSDH ?? (lowered.contains("sdh") || lowered.contains("hearing") || lowered.contains("[cc]") || lowered.hasSuffix(" cc"))
    }

    /// The label shown in track menus: language first, details after, never jargon.
    ///
    /// Examples: "English", "English (SDH)", "Japanese · 5.1", "Commentary".
    public func displayName(locale: Locale = .current) -> String {
        var title: String
        if let code = languageCode,
           let language = MediaTrack.languageName(for: code, locale: locale) {
            title = language
        } else {
            title = MediaTrack.cleanedEngineName(name)
        }
        if title.isEmpty {
            title = kind == .subtitle ? "Subtitle" : "Track"
        }

        var qualifiers: [String] = []
        if isSDH { qualifiers.append("SDH") }
        if isForced { qualifiers.append("Forced") }
        if isExternal { qualifiers.append("External") }
        if !qualifiers.isEmpty {
            title += " (\(qualifiers.joined(separator: ", ")))"
        }
        if kind == .audio, let layout = MediaTrack.channelLayoutName(channelCount) {
            title += " \u{00B7} \(layout)"
        }
        return title
    }

    /// "en" / "eng" / "pt-BR" → "English" / "English" / "Portuguese (Brazil)".
    public static func languageName(for code: String, locale: Locale = .current) -> String? {
        let trimmed = code.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.lowercased() != "und", trimmed.lowercased() != "unknown" else {
            return nil
        }
        if let name = locale.localizedString(forIdentifier: trimmed), !name.isEmpty,
           name.lowercased() != trimmed.lowercased() {
            return name.prefix(1).uppercased() + name.dropFirst()
        }
        if let name = locale.localizedString(forLanguageCode: trimmed), !name.isEmpty,
           name.lowercased() != trimmed.lowercased() {
            return name.prefix(1).uppercased() + name.dropFirst()
        }
        return nil
    }

    /// Reduces any language tag to its base ISO 639-1 code where one exists:
    /// "eng", "en-US" and "en" all become "en"; bibliographic ISO 639-2 codes
    /// such as "fre" or "ger" are mapped too. The two engines report languages
    /// differently (AVFoundation uses BCP-47, VLC whatever the file declares).
    public static func normalizedLanguageCode(_ code: String) -> String {
        let trimmed = code.trimmingCharacters(in: .whitespaces).lowercased()
        let base = String(trimmed.split(whereSeparator: { $0 == "-" || $0 == "_" }).first ?? "")
        if let mapped = bibliographicCodes[base] {
            return mapped
        }
        let languageCode = Locale.Language(identifier: base).languageCode
        return languageCode?.identifier(.alpha2) ?? base
    }

    /// `true` when both tags name the same language ("eng" matches "en-GB").
    public static func languagesMatch(_ lhs: String?, _ rhs: String?) -> Bool {
        guard let lhs, let rhs, !lhs.isEmpty, !rhs.isEmpty else { return false }
        return normalizedLanguageCode(lhs) == normalizedLanguageCode(rhs)
    }

    /// ISO 639-2/B codes that differ from their 639-2/T form.
    private static let bibliographicCodes: [String: String] = [
        "alb": "sq", "arm": "hy", "baq": "eu", "bur": "my", "chi": "zh", "cze": "cs",
        "dut": "nl", "fre": "fr", "geo": "ka", "ger": "de", "gre": "el", "ice": "is",
        "mac": "mk", "mao": "mi", "may": "ms", "per": "fa", "rum": "ro", "slo": "sk",
        "tib": "bo", "wel": "cy",
    ]

    /// 1 → "Mono", 2 → "Stereo", 6 → "5.1", 8 → "7.1".
    public static func channelLayoutName(_ channels: Int?) -> String? {
        switch channels {
        case 1: "Mono"
        case 2: "Stereo"
        case 6: "5.1"
        case 7: "6.1"
        case 8: "7.1"
        default: nil
        }
    }

    /// Strips VLC's "Track 1 - " prefixes and "[eng]" suffixes from engine names.
    static func cleanedEngineName(_ name: String) -> String {
        var result = name
        if let range = result.range(of: #"^Track \d+\s*-\s*"#, options: .regularExpression) {
            result.removeSubrange(range)
        }
        if let range = result.range(of: #"\s*\[[^\]]*\]\s*$"#, options: .regularExpression),
           range.lowerBound != result.startIndex {
            result.removeSubrange(range)
        }
        return result.trimmingCharacters(in: .whitespaces)
    }
}

/// A chapter marker inside the playing media.
public struct Chapter: Identifiable, Hashable, Sendable {
    public let id: Int
    public var title: String?
    public var start: TimeInterval
    public var duration: TimeInterval

    public init(index: Int, title: String?, start: TimeInterval, duration: TimeInterval) {
        self.id = index
        self.title = title
        self.start = start
        self.duration = duration
    }

    public var displayTitle: String {
        if let title, !title.isEmpty { return title }
        return "Chapter \(id + 1)"
    }
}

/// Tags embedded in the media (ID3, Vorbis comments, MP4 atoms…), as read by the engine.
public struct MediaMetadata: Hashable, Sendable {
    public var title: String?
    public var artist: String?
    public var albumTitle: String?
    public var albumArtist: String?
    public var genre: String?
    public var trackNumber: Int?
    public var discNumber: Int?
    /// Encoded image data (JPEG or PNG).
    public var artworkData: Data?

    public init(
        title: String? = nil,
        artist: String? = nil,
        albumTitle: String? = nil,
        albumArtist: String? = nil,
        genre: String? = nil,
        trackNumber: Int? = nil,
        discNumber: Int? = nil,
        artworkData: Data? = nil
    ) {
        self.title = title
        self.artist = artist
        self.albumTitle = albumTitle
        self.albumArtist = albumArtist
        self.genre = genre
        self.trackNumber = trackNumber
        self.discNumber = discNumber
        self.artworkData = artworkData
    }

    public var isEmpty: Bool {
        title == nil && artist == nil && albumTitle == nil && artworkData == nil
    }
}
