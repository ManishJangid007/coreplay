import Foundation

/// A four-character code such as `avc1`, `hvc1` or `ac-3`.
public struct FourCC: Hashable, Sendable, CustomStringConvertible, ExpressibleByStringLiteral {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    /// Builds a code from up to four ASCII characters. Shorter strings are
    /// padded with spaces, so `"aac"` becomes `"aac "`.
    public init(_ string: String) {
        var value: UInt32 = 0
        let bytes = Array(string.utf8.prefix(4)) + Array(repeating: UInt8(ascii: " "), count: max(0, 4 - string.utf8.count))
        for byte in bytes {
            value = (value << 8) | UInt32(byte)
        }
        self.rawValue = value
    }

    public init(stringLiteral value: String) {
        self.init(value)
    }

    public var description: String {
        let bytes = [
            UInt8((rawValue >> 24) & 0xFF),
            UInt8((rawValue >> 16) & 0xFF),
            UInt8((rawValue >> 8) & 0xFF),
            UInt8(rawValue & 0xFF),
        ]
        if bytes.allSatisfy({ $0 >= 0x20 && $0 < 0x7F }) {
            return String(decoding: bytes, as: UTF8.self)
        }
        return String(format: "0x%08X", rawValue)
    }
}

/// Codecs AVFoundation decodes on iOS 26 and macOS 26.
///
/// Deliberately conservative: anything not listed goes to VLC, which plays it
/// anyway. A track must also report `isPlayable` from AVFoundation before the
/// router trusts it.
public enum NativeCodecSupport {
    public static let video: Set<FourCC> = [
        "avc1", "avc3",                         // H.264
        "hvc1", "hev1",                         // HEVC
        "dvh1", "dvhe", "dva1", "dvav",         // Dolby Vision (HEVC / AVC based)
        "mp4v",                                 // MPEG-4 Part 2
        "jpeg", "mjpa",                         // Motion JPEG
        "apcn", "apch", "apcs", "apco", "ap4h", "ap4x", "aprn", "aprh", // ProRes family
    ]

    public static let audio: Set<FourCC> = [
        "aac ", "mp4a", "aach", "aacl", "aacp", "aace", "aacf", "aacg", "aacs", "xhe1", // AAC family
        ".mp3",                                 // MP3
        "alac",                                 // Apple Lossless
        "flac",                                 // FLAC
        "ac-3", "ec-3",                         // Dolby Digital / Dolby Digital Plus (incl. Atmos JOC)
        "lpcm", "sowt", "twos", "in24", "in32", "fl32", "fl64", "raw ", // PCM variants
        "ulaw", "alaw", "ima4",                 // Telephony / legacy QuickTime
        "samr", "sawb",                         // AMR
    ]

    /// Subtitle and caption formats AVFoundation renders itself.
    public static let text: Set<FourCC> = [
        "tx3g",                                 // 3GPP timed text (mov_text)
        "wvtt",                                 // WebVTT in MP4
        "c608", "c708",                         // CEA-608 / 708 closed captions
        "text",                                 // QuickTime text
        "sbtl",                                 // QuickTime subtitle
    ]
}
