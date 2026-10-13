import Foundation

/// What's inside the playing media, stream by stream: VLC's Codec
/// Information, in plain language. Shown on the player's Media Info page.
public struct MediaInfo: Hashable, Sendable {
    public struct Stream: Hashable, Sendable, Identifiable {
        public enum Kind: String, Hashable, Sendable {
            case video
            case audio
            case subtitle
        }

        public var id: String
        public var kind: Kind
        /// Readable codec name, e.g. "HEVC" or "Dolby Digital Plus".
        public var codec: String?
        /// The four-character code it came from, e.g. "hvc1".
        public var fourCC: String?
        /// Language code as the file gives it.
        public var language: String?
        /// The track's own name in the file ("Commentary").
        public var title: String?
        /// Bits per second, when the file says.
        public var bitrate: Int?
        public var isSelected: Bool

        // Video
        public var width: Int?
        public var height: Int?
        public var frameRate: Double?
        /// "HDR10", "HLG", "Dolby Vision"; `nil` when unknown or standard.
        public var dynamicRange: String?
        /// Clockwise rotation the file asks for, in degrees.
        public var rotation: Int?
        /// 360° (equirectangular) video.
        public var isSpherical: Bool

        // Audio
        public var channels: Int?
        public var sampleRate: Int?

        // Subtitles
        /// Text encoding VLC detected, e.g. "UTF-8".
        public var textEncoding: String?

        public init(
            id: String,
            kind: Kind,
            codec: String? = nil,
            fourCC: String? = nil,
            language: String? = nil,
            title: String? = nil,
            bitrate: Int? = nil,
            isSelected: Bool = false,
            width: Int? = nil,
            height: Int? = nil,
            frameRate: Double? = nil,
            dynamicRange: String? = nil,
            rotation: Int? = nil,
            isSpherical: Bool = false,
            channels: Int? = nil,
            sampleRate: Int? = nil,
            textEncoding: String? = nil
        ) {
            self.id = id
            self.kind = kind
            self.codec = codec
            self.fourCC = fourCC
            self.language = language
            self.title = title
            self.bitrate = bitrate
            self.isSelected = isSelected
            self.width = width
            self.height = height
            self.frameRate = frameRate
            self.dynamicRange = dynamicRange
            self.rotation = rotation
            self.isSpherical = isSpherical
            self.channels = channels
            self.sampleRate = sampleRate
            self.textEncoding = textEncoding
        }

        /// "English", "English · Commentary", or "Track 2".
        public func displayName(index: Int, locale: Locale = .current) -> String {
            var parts: [String] = []
            if let language, let name = MediaTrack.languageName(for: language, locale: locale) {
                parts.append(name)
            }
            if let title, !title.isEmpty, !parts.contains(title) {
                parts.append(title)
            }
            return parts.isEmpty ? "Track \(index + 1)" : parts.joined(separator: " \u{00B7} ")
        }
    }

    public var streams: [Stream]

    public init(streams: [Stream] = []) {
        self.streams = streams
    }

    public var video: [Stream] { streams.filter { $0.kind == .video } }
    public var audio: [Stream] { streams.filter { $0.kind == .audio } }
    public var subtitles: [Stream] { streams.filter { $0.kind == .subtitle } }
}

/// Live figures from the engine, for the Media Info page.
public struct PlaybackStatistics: Hashable, Sendable {
    /// Bits per second read from the file or network right now.
    public var inputBitrate: Double
    public var displayedPictures: Int
    /// Pictures shown late or dropped.
    public var lostPictures: Int
    public var lostAudioBuffers: Int

    public init(inputBitrate: Double, displayedPictures: Int, lostPictures: Int, lostAudioBuffers: Int) {
        self.inputBitrate = inputBitrate
        self.displayedPictures = displayedPictures
        self.lostPictures = lostPictures
        self.lostAudioBuffers = lostAudioBuffers
    }
}

/// Readable names for codec four-character codes, from AVFoundation
/// (`avc1`, `ec-3`) and libVLC (`h264`, `a52 `) alike.
public enum CodecNames {
    public static func name(for fourCC: String) -> String? {
        names[fourCC] ?? names[fourCC.lowercased()] ?? names[fourCC.trimmingCharacters(in: .whitespaces).lowercased()]
    }

    private static let names: [String: String] = {
        var table: [String: String] = [:]
        func add(_ codes: [String], _ name: String) {
            for code in codes {
                table[code] = name
                table[code.lowercased()] = name
            }
        }
        // Video
        add(["avc1", "avc3", "h264", "x264", "davc"], "H.264")
        add(["hvc1", "hev1", "hevc", "h265", "x265"], "HEVC")
        add(["dvh1", "dvhe"], "Dolby Vision (HEVC)")
        add(["dva1", "dvav"], "Dolby Vision (H.264)")
        add(["av01", "av1"], "AV1")
        add(["vp09", "vp90", "vp9"], "VP9")
        add(["vp08", "vp80", "vp8"], "VP8")
        add(["mp4v", "fmp4", "xvid", "divx", "dx50", "mp4s", "m4s2"], "MPEG-4 Part 2")
        add(["mpgv", "mp2v", "mpg2", "mpeg2", "m2v1"], "MPEG-2")
        add(["mp1v", "mpg1"], "MPEG-1")
        add(["apcn", "apch", "apcs", "apco", "ap4h", "ap4x", "aprn", "aprh"], "ProRes")
        add(["theo"], "Theora")
        add(["wmv1"], "Windows Media Video 7")
        add(["wmv2"], "Windows Media Video 8")
        add(["wmv3"], "Windows Media Video 9")
        add(["wvc1", "vc-1"], "VC-1")
        add(["mjpg", "jpeg", "mjpa"], "Motion JPEG")
        add(["h263", "s263"], "H.263")
        add(["vvc1", "vvi1", "h266"], "VVC")
        // Audio
        add(["mp4a", "aac ", "aac", "aach", "aacl", "aacp"], "AAC")
        add([".mp3", "mp3 ", "mp3", "mpga"], "MP3")
        add(["mp2a", "mp2 "], "MPEG Audio Layer 2")
        add(["ac-3", "a52 ", "a52", "ac3 ", "ac3"], "Dolby Digital")
        add(["ec-3", "eac3", "a52b"], "Dolby Digital Plus")
        add(["ac-4", "ac4 "], "Dolby AC-4")
        add(["mlp ", "mlp", "trhd", "truehd"], "Dolby TrueHD")
        add(["dts ", "dts", "dtsc", "dtsh", "dtsl", "dtse"], "DTS")
        add(["flac"], "FLAC")
        add(["alac"], "Apple Lossless")
        add(["opus"], "Opus")
        add(["vorb"], "Vorbis")
        add(["lpcm", "araw", "sowt", "twos", "in24", "in32", "fl32", "fl64", "s16l", "s16b", "s24l", "s24b", "s32l", "f32l"], "PCM")
        add(["wma1", "wma2", "wmap", "wmal"], "Windows Media Audio")
        add(["samr", "sawb"], "AMR")
        add(["ape ", "apac"], "Monkey's Audio")
        add(["wvpk"], "WavPack")
        // Subtitles
        add(["subt"], "Text")
        add(["ssa ", "ass ", "ass"], "SubStation Alpha")
        add(["tx3g", "text"], "Timed Text")
        add(["wvtt", "webv"], "WebVTT")
        add(["ttml", "stpp"], "TTML")
        add(["spu ", "dvds"], "DVD (VobSub)")
        add(["pgs ", "pgss"], "Blu-ray (PGS)")
        add(["dvbs"], "DVB")
        add(["c608", "cc1 "], "CEA-608")
        add(["c708"], "CEA-708")
        add(["scte"], "SCTE-27")
        return table
    }()
}

/// How Media Info shows numbers.
public enum MediaInfoFormat {
    /// "640 kb/s", "4.5 Mb/s".
    public static func bitrate(_ bitsPerSecond: Double) -> String {
        if bitsPerSecond >= 1_000_000 {
            return "\((bitsPerSecond / 1_000_000).formatted(.number.precision(.fractionLength(0...1)))) Mb/s"
        }
        return "\(Int((bitsPerSecond / 1_000).rounded())) kb/s"
    }

    /// "23.976 fps", "25 fps".
    public static func frameRate(_ rate: Double) -> String {
        "\(rate.formatted(.number.precision(.fractionLength(0...3)))) fps"
    }

    /// "48 kHz", "44.1 kHz".
    public static func sampleRate(_ hertz: Int) -> String {
        "\((Double(hertz) / 1_000).formatted(.number.precision(.fractionLength(0...1)))) kHz"
    }

    /// "Stereo", "5.1", or "3 channels".
    public static func channels(_ count: Int) -> String {
        MediaTrack.channelLayoutName(count) ?? "\(count) channels"
    }

    /// "1.2 GB", "640 MB".
    public static func fileSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
