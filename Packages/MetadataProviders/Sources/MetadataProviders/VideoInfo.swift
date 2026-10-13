import Foundation

/// What's inside a video file, read from its container headers (no decoding):
/// running time, picture size and format, audio and subtitle tracks, and
/// the recording date and place cameras store.
///
/// Feeds the badges on detail pages (4K, HDR, Dolby Vision, Dolby Atmos,
/// 5.1, CC), runtimes before a video has ever been played, and home video
/// dates.
public struct VideoInfo: Sendable, Equatable {
    public enum DynamicRange: String, Sendable, Codable, CaseIterable {
        case sdr
        case hdr10
        case hdr10Plus
        case hlg
        case dolbyVision

        /// The badge the TV app shows, or `nil` for SDR.
        public var badge: String? {
            switch self {
            case .sdr: nil
            case .hdr10: "HDR10"
            case .hdr10Plus: "HDR10+"
            case .hlg: "HLG"
            case .dolbyVision: "Dolby Vision"
            }
        }
    }

    public struct AudioTrack: Sendable, Equatable, Codable {
        public var codec: String
        public var channels: Int?
        /// ISO 639-2 or BCP 47 code; `nil` when undetermined.
        public var language: String?
        public var title: String?
        public var isAtmos: Bool
        public var isDefault: Bool

        public init(codec: String, channels: Int? = nil, language: String? = nil, title: String? = nil, isAtmos: Bool = false, isDefault: Bool = false) {
            self.codec = codec
            self.channels = channels
            self.language = language
            self.title = title
            self.isAtmos = isAtmos
            self.isDefault = isDefault
        }
    }

    public struct SubtitleTrack: Sendable, Equatable, Codable {
        public var codec: String
        public var language: String?
        public var title: String?
        public var isForced: Bool
        public var isHearingImpaired: Bool

        public init(codec: String, language: String? = nil, title: String? = nil, isForced: Bool = false, isHearingImpaired: Bool = false) {
            self.codec = codec
            self.language = language
            self.title = title
            self.isForced = isForced
            self.isHearingImpaired = isHearingImpaired
        }
    }

    /// "MP4", "QuickTime", "Matroska", "WebM" or "AVI".
    public var container: String
    public var duration: TimeInterval?
    public var width: Int?
    public var height: Int?
    public var frameRate: Double?
    /// "HEVC", "H.264", "AV1"…
    public var videoCodec: String?
    public var dynamicRange: DynamicRange?
    public var audioTracks: [AudioTrack] = []
    public var subtitleTracks: [SubtitleTrack] = []
    /// The title stored in the container, if any.
    public var title: String?
    /// When the video was recorded (cameras and phones store this).
    public var creationDate: Date?
    /// Where it was recorded, as ISO 6709 ("+37.7858-122.4064+010.000/").
    public var location: String?
    /// Cover art embedded in the file (Matroska attachments, MP4 `covr`).
    public var coverArt: Data?
    public var chapterCount: Int?

    public init(container: String) {
        self.container = container
    }

    /// "8K", "4K", "HD" or "SD".
    public var resolutionBadge: String? {
        guard let width, let height, width > 0, height > 0 else { return nil }
        if width >= 6_000 || height >= 3_400 { return "8K" }
        if width >= 3_200 || height >= 1_800 { return "4K" }
        if width >= 1_200 || height >= 700 { return "HD" }
        return "SD"
    }

    /// The most channels any audio track has.
    public var maximumAudioChannels: Int? {
        audioTracks.compactMap(\.channels).max()
    }

    public var hasAtmos: Bool {
        audioTracks.contains(where: \.isAtmos)
    }
}

/// Reads `VideoInfo` from MP4/MOV/M4V, Matroska/WebM and AVI files.
public enum VideoProbe {
    public static func read(url: URL) throws -> VideoInfo? {
        try read(FileByteSource(url: url))
    }

    /// `nil` for containers it doesn't know (the player still plays them).
    public static func read(_ source: ByteSource) throws -> VideoInfo? {
        let magic = try source.bytes(at: 0, count: 16)
        if magic.count >= 4, magic[0] == 0x1A, magic[1] == 0x45, magic[2] == 0xDF, magic[3] == 0xA3 {
            return try Matroska.read(source)
        }
        if Bytes.matches(magic, 0, "RIFF"), Bytes.matches(magic, 8, "AVI ") {
            return try AVI.read(source)
        }
        if Bytes.matches(magic, 4, "ftyp") || Bytes.matches(magic, 4, "moov") || Bytes.matches(magic, 4, "mdat")
            || Bytes.matches(magic, 4, "wide") || Bytes.matches(magic, 4, "free") || Bytes.matches(magic, 4, "skip") {
            return try MP4.videoInfo(source, brand: Bytes.matches(magic, 4, "ftyp") ? Bytes.fourCC(magic, 8) : nil)
        }
        return nil
    }

    /// Language codes that mean "not specified".
    static func language(_ code: String?) -> String? {
        guard let code = code?.trimmingCharacters(in: .whitespacesAndNewlines), !code.isEmpty else { return nil }
        switch code.lowercased() {
        case "und", "unk", "mis", "zxx", "mul", "xx", "none": return nil
        default: return code
        }
    }

    /// Dolby Atmos is signalled in track names by most muxers.
    static func namesAtmos(_ title: String?) -> Bool {
        title?.range(of: "atmos", options: .caseInsensitive) != nil
    }
}

/// Reads bit fields, most significant bit first.
struct BitReader {
    private let bytes: [UInt8]
    private var bitPosition = 0

    init(_ bytes: [UInt8]) {
        self.bytes = bytes
    }

    init(_ bytes: ArraySlice<UInt8>) {
        self.bytes = Array(bytes)
    }

    var bitsRemaining: Int { bytes.count * 8 - bitPosition }

    mutating func read(_ count: Int) -> UInt32? {
        guard count <= 32, count <= bitsRemaining else { return nil }
        var value: UInt32 = 0
        for _ in 0..<count {
            let byte = bytes[bitPosition / 8]
            let bit = (byte >> (7 - UInt8(bitPosition % 8))) & 1
            value = value << 1 | UInt32(bit)
            bitPosition += 1
        }
        return value
    }
}

/// Dates written by cameras and phones: "2024-03-15T10:12:34+0100",
/// "2024-03-15T10:12:34Z", "2024-03-15 10:12:34".
enum MediaDate {
    static func parse(_ text: String) -> Date? {
        let scalars = Array(text.trimmingCharacters(in: .whitespacesAndNewlines))
        func number(_ start: Int, _ length: Int) -> Int? {
            guard start >= 0, start + length <= scalars.count else { return nil }
            let slice = scalars[start..<(start + length)]
            guard slice.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
            return Int(String(slice))
        }
        guard let year = number(0, 4), let month = number(5, 2), let day = number(8, 2),
              (1900...2200).contains(year), (1...12).contains(month), (1...31).contains(day) else { return nil }
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = number(11, 2) ?? 0
        components.minute = number(14, 2) ?? 0
        components.second = number(17, 2) ?? 0
        var offsetSeconds = 0
        var index = 19
        // Fractional seconds.
        if index < scalars.count, scalars[index] == "." {
            index += 1
            while index < scalars.count, scalars[index].isNumber { index += 1 }
        }
        if index < scalars.count {
            let sign = scalars[index]
            if sign == "+" || sign == "-" {
                let hours = number(index + 1, 2) ?? 0
                let minuteStart = index + 3 < scalars.count && scalars[index + 3] == ":" ? index + 4 : index + 3
                let minutes = number(minuteStart, 2) ?? 0
                offsetSeconds = (hours * 3_600 + minutes * 60) * (sign == "-" ? -1 : 1)
            }
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: offsetSeconds) ?? TimeZone(secondsFromGMT: 0)!
        return calendar.date(from: components)
    }
}
