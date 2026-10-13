import Foundation

/// Everything Coreplay reads from an audio file's embedded tags.
///
/// Every field is optional: files carry anything from a complete set of tags
/// to nothing at all. `TagReader` fills what it can; the library falls back to
/// folder and file names (`PathMetadata`) for the rest.
public struct AudioTags: Sendable, Hashable {
    public var title: String?
    public var artist: String?
    public var album: String?
    public var albumArtist: String?
    public var composer: String?
    public var genre: String?
    public var year: Int?
    public var trackNumber: Int?
    public var trackCount: Int?
    public var discNumber: Int?
    public var discCount: Int?
    public var isCompilation: Bool?
    public var lyrics: String?
    public var comment: String?
    public var sortTitle: String?
    public var sortArtist: String?
    public var sortAlbum: String?
    public var sortAlbumArtist: String?
    public var musicBrainzRecordingID: String?
    public var musicBrainzAlbumID: String?
    public var musicBrainzArtistID: String?
    /// The best embedded picture (the front cover when the file says which one that is).
    public var artwork: EmbeddedArtwork?
    /// Playing time in seconds, from stream headers (not from a tag) where possible.
    public var duration: TimeInterval?
    public var format: AudioFormatInfo?

    public init() {}

    /// `true` when no descriptive tag was found (format and duration don't count).
    public var hasDescriptiveTags: Bool {
        title != nil || artist != nil || album != nil || albumArtist != nil || trackNumber != nil
    }

    /// Fills fields that are still empty from `other`, which has lower priority.
    public mutating func fillMissing(from other: AudioTags) {
        title = title ?? other.title
        artist = artist ?? other.artist
        album = album ?? other.album
        albumArtist = albumArtist ?? other.albumArtist
        composer = composer ?? other.composer
        genre = genre ?? other.genre
        year = year ?? other.year
        trackNumber = trackNumber ?? other.trackNumber
        trackCount = trackCount ?? other.trackCount
        discNumber = discNumber ?? other.discNumber
        discCount = discCount ?? other.discCount
        isCompilation = isCompilation ?? other.isCompilation
        lyrics = lyrics ?? other.lyrics
        comment = comment ?? other.comment
        sortTitle = sortTitle ?? other.sortTitle
        sortArtist = sortArtist ?? other.sortArtist
        sortAlbum = sortAlbum ?? other.sortAlbum
        sortAlbumArtist = sortAlbumArtist ?? other.sortAlbumArtist
        musicBrainzRecordingID = musicBrainzRecordingID ?? other.musicBrainzRecordingID
        musicBrainzAlbumID = musicBrainzAlbumID ?? other.musicBrainzAlbumID
        musicBrainzArtistID = musicBrainzArtistID ?? other.musicBrainzArtistID
        artwork = artwork ?? other.artwork
        duration = duration ?? other.duration
        format = format ?? other.format
    }
}

/// A picture stored inside an audio file.
public struct EmbeddedArtwork: Sendable, Hashable {
    /// ID3 / FLAC picture types. Only the ones Coreplay cares about are named.
    public enum PictureType: Int, Sendable, Hashable {
        case other = 0
        case frontCover = 3
        case backCover = 4
        case artist = 8
    }

    public var data: Data
    public var mimeType: String?
    /// The raw ID3 / FLAC picture type (3 is the front cover).
    public var pictureType: Int

    public init(data: Data, mimeType: String? = nil, pictureType: Int = PictureType.frontCover.rawValue) {
        self.data = data
        self.mimeType = mimeType
        self.pictureType = pictureType
    }

    var isFrontCover: Bool { pictureType == PictureType.frontCover.rawValue }

    /// Picks the front cover if there is one, otherwise the first usable picture.
    static func best(of pictures: [EmbeddedArtwork]) -> EmbeddedArtwork? {
        let usable = pictures.filter { !$0.data.isEmpty }
        return usable.first(where: \.isFrontCover) ?? usable.first
    }
}

/// How the audio itself is encoded, for "Lossless" and "Hi-Res" badges.
public struct AudioFormatInfo: Sendable, Hashable {
    /// A short, user-facing codec name: "MP3", "AAC", "ALAC", "FLAC", "Opus"…
    public var codec: String
    public var sampleRate: Int?
    public var channels: Int?
    public var bitsPerSample: Int?
    /// Average bit rate in bits per second, when known.
    public var bitRate: Int?
    public var isLossless: Bool

    public init(codec: String, sampleRate: Int? = nil, channels: Int? = nil, bitsPerSample: Int? = nil, bitRate: Int? = nil, isLossless: Bool) {
        self.codec = codec
        self.sampleRate = sampleRate
        self.channels = channels
        self.bitsPerSample = bitsPerSample
        self.bitRate = bitRate
        self.isLossless = isLossless
    }

    /// Lossless with more than 16 bits per sample or a sample rate above
    /// 48 kHz, the files Apple Music labels Hi-Res Lossless.
    public var isHighResolution: Bool {
        guard isLossless else { return false }
        return (bitsPerSample ?? 0) > 16 || (sampleRate ?? 0) > 48_000
    }
}

// MARK: - Text helpers shared by the readers

enum Text {
    static func latin1(_ bytes: ArraySlice<UInt8>) -> String {
        String(String.UnicodeScalarView(bytes.map { Unicode.Scalar($0) }))
    }

    static func utf8(_ bytes: ArraySlice<UInt8>) -> String {
        String(decoding: bytes, as: UTF8.self)
    }

    /// UTF-16 with an optional byte-order mark; without one, `bigEndian` decides.
    static func utf16(_ bytes: ArraySlice<UInt8>, bigEndian defaultBigEndian: Bool) -> String {
        var slice = bytes
        var bigEndian = defaultBigEndian
        if slice.count >= 2 {
            let first = slice[slice.startIndex]
            let second = slice[slice.startIndex + 1]
            if first == 0xFF, second == 0xFE {
                bigEndian = false
                slice = slice.dropFirst(2)
            } else if first == 0xFE, second == 0xFF {
                bigEndian = true
                slice = slice.dropFirst(2)
            }
        }
        var units: [UInt16] = []
        units.reserveCapacity(slice.count / 2)
        var index = slice.startIndex
        while index + 1 < slice.endIndex {
            let a = UInt16(slice[index])
            let b = UInt16(slice[index + 1])
            units.append(bigEndian ? (a << 8 | b) : (b << 8 | a))
            index += 2
        }
        return String(decoding: units, as: UTF16.self)
    }

    /// Trims whitespace and stray NULs; `nil` when nothing is left.
    static func cleaned(_ string: String?) -> String? {
        guard let string else { return nil }
        let trimmed = string
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{0}")))
        return trimmed.isEmpty ? nil : trimmed
    }

    /// "3", "03", "3/12" → (3, 12). Zero means "not set".
    static func numberPair(_ string: String?) -> (Int?, Int?) {
        guard let string = cleaned(string) else { return (nil, nil) }
        let parts = string.split(separator: "/", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        func number(_ part: String?) -> Int? {
            guard let part, let value = Int(part.prefix(while: \.isNumber)), value > 0 else { return nil }
            return value
        }
        return (number(parts.first), number(parts.count > 1 ? parts[1] : nil))
    }

    /// The first four-digit year in a date such as "2004", "2004-05-01" or "05/01/2004".
    static func year(_ string: String?) -> Int? {
        guard let string = cleaned(string) else { return nil }
        let digits = Array(string)
        var index = 0
        while index + 4 <= digits.count {
            let candidate = digits[index..<(index + 4)]
            if candidate.allSatisfy(\.isNumber),
               index + 4 == digits.count || !digits[index + 4].isNumber,
               index == 0 || !digits[index - 1].isNumber,
               let value = Int(String(candidate)), (1000...2999).contains(value) {
                return value
            }
            index += 1
        }
        return nil
    }

    static func bool(_ string: String?) -> Bool? {
        guard let value = cleaned(string)?.lowercased() else { return nil }
        switch value {
        case "1", "true", "yes": return true
        case "0", "false", "no": return false
        default: return nil
        }
    }

    /// Guesses an image MIME type from its first bytes.
    static func imageMIMEType(_ data: Data) -> String? {
        let bytes = [UInt8](data.prefix(12))
        if bytes.starts(with: [0xFF, 0xD8, 0xFF]) { return "image/jpeg" }
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "image/png" }
        if bytes.starts(with: Array("GIF8".utf8)) { return "image/gif" }
        if bytes.starts(with: Array("BM".utf8)) { return "image/bmp" }
        if bytes.count >= 12, bytes.starts(with: Array("RIFF".utf8)), Array(bytes[8..<12]) == Array("WEBP".utf8) { return "image/webp" }
        return nil
    }
}
