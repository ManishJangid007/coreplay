import Foundation

/// What a DVD-Video's IFO files say: its titles with their chapters and
/// running times, whether it has menus, and the main title's picture, sound
/// and subtitles. The library reads it for DVD folders and images, which
/// have no container for `VideoProbe` to read.
public struct DVDVideoInfo: Hashable, Sendable {
    public struct Title: Hashable, Sendable {
        /// 1-based, as the disc numbers them.
        public var number: Int
        public var titleSet: Int
        public var chapters: Int
        public var angles: Int
        public var duration: TimeInterval
    }

    public struct Video: Hashable, Sendable {
        /// "MPEG-2" (or "MPEG-1").
        public var codec: String
        public var width: Int
        public var height: Int
        /// 16:9 rather than 4:3.
        public var isWidescreen: Bool
        /// 25 for PAL, 29.97 for NTSC.
        public var frameRate: Double
    }

    public struct Audio: Hashable, Sendable {
        /// "AC-3", "DTS", "LPCM" or "MPEG Audio".
        public var codec: String
        public var channels: Int
        /// ISO 639-1 ("en"), when the disc says.
        public var language: String?
        public var isCommentary: Bool
    }

    public struct Subtitle: Hashable, Sendable {
        public var language: String?
    }

    public var titles: [Title]
    /// The disc has menus (the VMG's, or a title set's).
    public var hasMenu: Bool
    /// The main title's title set's picture, sound and subtitles.
    public var video: Video?
    public var audio: [Audio]
    public var subtitles: [Subtitle]

    /// The film: the longest title.
    public var mainTitle: Title? {
        titles.max { $0.duration < $1.duration }
    }

    /// IFO files are a few kilobytes; anything bigger isn't one.
    public static let maximumIFOSize = 16 << 20

    /// Reads a DVD's folder or image.
    public static func read(_ disc: Disc) -> DVDVideoInfo? {
        guard let files = DiscLayout.videoTSFiles(of: disc) else { return nil }
        return read(files)
    }

    /// Reads VIDEO_TS.IFO and the title sets' IFOs; `file` returns a file
    /// in VIDEO_TS by its upper-case name.
    public static func read(_ file: (String) -> Data?) -> DVDVideoInfo? {
        guard let vmg = file("VIDEO_TS.IFO").map(BigEndianBytes.init), vmg.string(at: 0, length: 12) == "DVDVIDEO-VMG" else { return nil }
        var titleSets: [Int: BigEndianBytes] = [:]
        func titleSet(_ number: Int) -> BigEndianBytes? {
            if let cached = titleSets[number] { return cached }
            let name = String(format: "VTS_%02d_0.IFO", number)
            guard let data = file(name).map(BigEndianBytes.init), data.string(at: 0, length: 12) == "DVDVIDEO-VTS" else { return nil }
            titleSets[number] = data
            return data
        }

        // The title search pointer table: each title's set, chapters and angles.
        var titles: [Title] = []
        let table = Int(vmg.uint32(at: 0xC4)) * 2_048
        let count = Int(vmg.uint16(at: table))
        for index in 0..<min(count, 99) {
            let entry = table + 8 + index * 12
            guard entry + 12 <= vmg.count else { break }
            let setNumber = Int(vmg.uint8(at: entry + 6))
            let titleInSet = Int(vmg.uint8(at: entry + 7))
            var title = Title(
                number: index + 1,
                titleSet: setNumber,
                chapters: Int(vmg.uint16(at: entry + 2)),
                angles: max(1, Int(vmg.uint8(at: entry + 1))),
                duration: 0
            )
            if let set = titleSet(setNumber) {
                title.duration = duration(ofTitle: titleInSet, in: set)
            }
            titles.append(title)
        }
        guard !titles.isEmpty else { return nil }

        var info = DVDVideoInfo(titles: titles, hasMenu: vmg.uint32(at: 0xC8) != 0, video: nil, audio: [], subtitles: [])
        if let main = info.mainTitle, let set = titleSet(main.titleSet) {
            info.video = video(in: set)
            info.audio = audio(in: set)
            info.subtitles = subtitles(in: set)
            info.hasMenu = info.hasMenu || set.uint32(at: 0xD0) != 0
        }
        return info
    }

    /// A title's running time: its program chains' playback times (most
    /// titles have one; seamless-branching ones have a chain per chapter).
    private static func duration(ofTitle titleInSet: Int, in set: BigEndianBytes) -> TimeInterval {
        // VTS_PTT_SRPT: each title's chapters, as (program chain, program) pairs.
        let parts = Int(set.uint32(at: 0xC8)) * 2_048
        let titleCount = Int(set.uint16(at: parts))
        guard titleInSet >= 1, titleInSet <= titleCount else { return 0 }
        let lastByte = Int(set.uint32(at: parts + 4))
        let start = Int(set.uint32(at: parts + 8 + (titleInSet - 1) * 4))
        let end = titleInSet < titleCount ? Int(set.uint32(at: parts + 8 + titleInSet * 4)) : lastByte + 1
        guard start > 0, end > start else { return 0 }
        var chains: [Int] = []
        var offset = start
        while offset + 4 <= end, chains.count < 999 {
            let chain = Int(set.uint16(at: parts + offset))
            if chain > 0, !chains.contains(chain) {
                chains.append(chain)
            }
            offset += 4
        }

        // VTS_PGCIT: each program chain's playback time.
        let chainTable = Int(set.uint32(at: 0xCC)) * 2_048
        let chainCount = Int(set.uint16(at: chainTable))
        var total: TimeInterval = 0
        for chain in chains where chain <= chainCount {
            let pgc = chainTable + Int(set.uint32(at: chainTable + 8 + (chain - 1) * 8 + 4))
            total += playbackTime(set, at: pgc + 4)
        }
        return total
    }

    /// dvd_time_t: hours, minutes, seconds and frames in BCD; the top two
    /// bits of the frames give the rate (01: 25, 11: 29.97).
    static func playbackTime(_ bytes: BigEndianBytes, at offset: Int) -> TimeInterval {
        guard offset + 4 <= bytes.count else { return 0 }
        func bcd(_ value: UInt8) -> Int { Int(value >> 4) * 10 + Int(value & 0x0F) }
        let frameByte = bytes.uint8(at: offset + 3)
        let rate: Double = switch frameByte >> 6 {
        case 1: 25
        case 3: 30_000.0 / 1_001.0
        default: 0
        }
        let frames = rate > 0 ? Double(bcd(frameByte & 0x3F)) / rate : 0
        return TimeInterval(bcd(bytes.uint8(at: offset)) * 3_600 + bcd(bytes.uint8(at: offset + 1)) * 60 + bcd(bytes.uint8(at: offset + 2))) + frames
    }

    /// vts_video_attr at 0x200.
    private static func video(in set: BigEndianBytes) -> Video? {
        guard set.count > 0x202 else { return nil }
        let first = set.uint8(at: 0x200)
        let second = set.uint8(at: 0x201)
        let isPAL = (first >> 4) & 0x03 == 1
        let fullHeight = isPAL ? 576 : 480
        let (width, height): (Int, Int) = switch (second >> 2) & 0x03 {
        case 0: (720, fullHeight)
        case 1: (704, fullHeight)
        case 2: (352, fullHeight)
        default: (352, fullHeight / 2)
        }
        return Video(
            codec: first >> 6 == 0 ? "MPEG-1" : "MPEG-2",
            width: width,
            height: height,
            isWidescreen: (first >> 2) & 0x03 == 3,
            frameRate: isPAL ? 25 : 30_000.0 / 1_001.0
        )
    }

    /// vts_audio_attr: up to eight streams of eight bytes from 0x204.
    private static func audio(in set: BigEndianBytes) -> [Audio] {
        let count = min(Int(set.uint8(at: 0x203)), 8)
        return (0..<count).compactMap { index in
            let offset = 0x204 + index * 8
            guard offset + 8 <= set.count else { return nil }
            let first = set.uint8(at: offset)
            let codec = switch first >> 5 {
            case 0: "AC-3"
            case 2, 3: "MPEG Audio"
            case 4: "LPCM"
            case 6: "DTS"
            default: "Audio"
            }
            let extensionCode = set.uint8(at: offset + 5)
            return Audio(
                codec: codec,
                channels: Int(set.uint8(at: offset + 1) & 0x07) + 1,
                language: (first >> 2) & 0x03 == 1 ? language(set, at: offset + 2) : nil,
                isCommentary: extensionCode == 3 || extensionCode == 4
            )
        }
    }

    /// vts_subp_attr: up to 32 streams of six bytes from 0x256.
    private static func subtitles(in set: BigEndianBytes) -> [Subtitle] {
        let count = min(Int(set.uint8(at: 0x255)), 32)
        return (0..<count).compactMap { index in
            let offset = 0x256 + index * 6
            guard offset + 6 <= set.count else { return nil }
            let hasLanguage = set.uint8(at: offset) & 0x03 == 1
            return Subtitle(language: hasLanguage ? language(set, at: offset + 2) : nil)
        }
    }

    private static func language(_ bytes: BigEndianBytes, at offset: Int) -> String? {
        let code = bytes.string(at: offset, length: 2).lowercased()
        guard code.count == 2, code.allSatisfy({ $0.isASCII && $0.isLetter }) else { return nil }
        return code
    }
}

/// What a Blu-ray folder's playlists (BDMV/PLAYLIST/*.mpls) say: each one's
/// length and chapters, and the longest one's picture, sound and subtitles.
public struct BlurayInfo: Hashable, Sendable {
    public struct Playlist: Hashable, Sendable {
        /// "00800".
        public var name: String
        public var duration: TimeInterval
        public var chapters: Int
        public var video: Video?
        public var audio: [Audio]
        /// ISO 639-2 codes ("eng"); `nil` when unknown.
        public var subtitles: [String?]
    }

    public struct Video: Hashable, Sendable {
        /// "H.264", "HEVC", "VC-1", "MPEG-2".
        public var codec: String
        public var width: Int
        public var height: Int
        public var frameRate: Double?
    }

    public struct Audio: Hashable, Sendable {
        /// "Dolby TrueHD", "DTS-HD MA", "AC-3", "LPCM"…
        public var codec: String
        public var channels: Int?
        /// ISO 639-2 ("eng").
        public var language: String?
    }

    public var playlists: [Playlist]

    /// The film: the longest playlist.
    public var mainPlaylist: Playlist? {
        playlists.max { $0.duration < $1.duration }
    }

    /// Reads a Blu-ray folder's playlists.
    public static func read(_ disc: Disc) -> BlurayInfo? {
        guard disc.kind == .bluray, !disc.isImage else { return nil }
        return read(folder: disc.root)
    }

    /// Reads a Blu-ray folder (the one holding BDMV).
    public static func read(folder: URL) -> BlurayInfo? {
        guard let bdmv = DiscLayout.entries(of: folder)["BDMV"],
              let playlistFolder = DiscLayout.entries(of: bdmv)["PLAYLIST"] else { return nil }
        var playlists: [Playlist] = []
        for (name, url) in DiscLayout.entries(of: playlistFolder) where name.hasSuffix(".MPLS") {
            guard let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, size < 4 << 20,
                  let data = try? Data(contentsOf: url),
                  let playlist = playlist(data, name: String(name.dropLast(5))) else { continue }
            playlists.append(playlist)
        }
        guard !playlists.isEmpty else { return nil }
        return BlurayInfo(playlists: playlists.sorted { $0.name < $1.name })
    }

    /// Parses one MPLS file: its play items' in and out times (45 kHz),
    /// its chapter marks, and the first item's stream table.
    public static func playlist(_ data: Data, name: String) -> Playlist? {
        let bytes = BigEndianBytes(data)
        guard bytes.string(at: 0, length: 4) == "MPLS" else { return nil }
        let listStart = Int(bytes.uint32(at: 8))
        let marksStart = Int(bytes.uint32(at: 12))
        guard listStart > 0, listStart + 10 <= bytes.count else { return nil }
        let itemCount = Int(bytes.uint16(at: listStart + 6))
        var offset = listStart + 10
        var ticks: Int64 = 0
        var video: Video?
        var audio: [Audio] = []
        var subtitles: [String?] = []
        for index in 0..<itemCount {
            guard offset + 2 <= bytes.count else { break }
            let length = Int(bytes.uint16(at: offset))
            let item = offset + 2
            guard item + 20 <= bytes.count, length >= 20 else { break }
            let inTime = Int64(bytes.uint32(at: item + 12))
            let outTime = Int64(bytes.uint32(at: item + 16))
            if outTime > inTime {
                ticks += outTime - inTime
            }
            if index == 0 {
                (video, audio, subtitles) = streams(bytes, playItem: item, end: item + length)
            }
            offset = item + length
        }
        var chapters = 0
        if marksStart > 0, marksStart + 6 <= bytes.count {
            let markCount = Int(bytes.uint16(at: marksStart + 4))
            for index in 0..<markCount {
                let mark = marksStart + 6 + index * 14
                guard mark + 14 <= bytes.count else { break }
                if bytes.uint8(at: mark + 1) == 1 { // an entry mark: a chapter
                    chapters += 1
                }
            }
        }
        return Playlist(name: name, duration: TimeInterval(ticks) / 45_000, chapters: chapters, video: video, audio: audio, subtitles: subtitles)
    }

    /// The play item's STN table: primary video, primary audio and
    /// presentation graphics (subtitle) streams.
    private static func streams(_ bytes: BigEndianBytes, playItem item: Int, end: Int) -> (Video?, [Audio], [String?]) {
        // name (5), codec (4), flags (2), STC id (1), in (4), out (4),
        // UO mask (8), random access (1), still mode (1), still time (2).
        var offset = item + 32
        guard offset <= end else { return (nil, [], []) }
        // 11 reserved bits, is_multi_angle, then the connection condition.
        let isMultiAngle = bytes.uint16(at: item + 9) & 0x0010 != 0
        if isMultiAngle {
            let angles = Int(bytes.uint8(at: offset))
            offset += 2 + max(0, angles - 1) * 10
        }
        let table = offset
        guard table + 16 <= end else { return (nil, [], []) }
        let videoCount = Int(bytes.uint8(at: table + 4))
        let audioCount = Int(bytes.uint8(at: table + 5))
        let graphicsCount = Int(bytes.uint8(at: table + 6))
        offset = table + 16

        var video: Video?
        var audio: [Audio] = []
        var subtitles: [String?] = []
        // Each stream: an entry (length byte + body) and attributes (length byte + body).
        func nextAttributes() -> (start: Int, length: Int)? {
            guard offset < end else { return nil }
            let entryLength = Int(bytes.uint8(at: offset))
            let attributes = offset + 1 + entryLength
            guard attributes < end else { return nil }
            let attributesLength = Int(bytes.uint8(at: attributes))
            offset = attributes + 1 + attributesLength
            guard offset <= end, attributesLength >= 1 else { return nil }
            return (attributes + 1, attributesLength)
        }
        for _ in 0..<videoCount {
            guard let attributes = nextAttributes() else { return (video, audio, subtitles) }
            guard video == nil, attributes.length >= 2 else { continue }
            let coding = bytes.uint8(at: attributes.start)
            let format = bytes.uint8(at: attributes.start + 1)
            video = Self.video(coding: coding, format: format >> 4, rate: format & 0x0F)
        }
        for _ in 0..<audioCount {
            guard let attributes = nextAttributes() else { return (video, audio, subtitles) }
            guard attributes.length >= 5 else { continue }
            let coding = bytes.uint8(at: attributes.start)
            let presentation = bytes.uint8(at: attributes.start + 1) >> 4
            let language = bytes.string(at: attributes.start + 2, length: 3).lowercased()
            let channels: Int? = switch presentation {
            case 1: 1
            case 3: 2
            case 6, 12: 6
            default: nil
            }
            audio.append(Audio(
                codec: audioCodec(coding),
                channels: channels,
                language: language.count == 3 && language.allSatisfy(\.isLetter) ? language : nil
            ))
        }
        for _ in 0..<graphicsCount {
            guard let attributes = nextAttributes() else { return (video, audio, subtitles) }
            let coding = bytes.uint8(at: attributes.start)
            // Presentation graphics carry the language straight after the
            // coding type; text subtitles have a character code first.
            let languageOffset = coding == 0x92 ? 2 : 1
            guard attributes.length >= languageOffset + 3 else {
                subtitles.append(nil)
                continue
            }
            let language = bytes.string(at: attributes.start + languageOffset, length: 3).lowercased()
            subtitles.append(language.count == 3 && language.allSatisfy(\.isLetter) ? language : nil)
        }
        return (video, audio, subtitles)
    }

    private static func video(coding: UInt8, format: UInt8, rate: UInt8) -> Video {
        let codec = switch coding {
        case 0x01: "MPEG-1"
        case 0x02: "MPEG-2"
        case 0x1B: "H.264"
        case 0x20: "H.264 MVC"
        case 0x24: "HEVC"
        case 0xEA: "VC-1"
        default: "Video"
        }
        let (width, height): (Int, Int) = switch format {
        case 1, 3: (720, 480)
        case 2, 7: (720, 576)
        case 4, 6: (1_920, 1_080)
        case 5: (1_280, 720)
        case 8: (3_840, 2_160)
        default: (0, 0)
        }
        let frameRate: Double? = switch rate {
        case 1: 24_000.0 / 1_001.0
        case 2: 24
        case 3: 25
        case 4: 30_000.0 / 1_001.0
        case 6: 50
        case 7: 60_000.0 / 1_001.0
        default: nil
        }
        return Video(codec: codec, width: width, height: height, frameRate: frameRate)
    }

    private static func audioCodec(_ coding: UInt8) -> String {
        switch coding {
        case 0x03, 0x04: "MPEG Audio"
        case 0x80: "LPCM"
        case 0x81: "AC-3"
        case 0x82: "DTS"
        case 0x83: "Dolby TrueHD"
        case 0x84, 0xA1: "E-AC-3"
        case 0x85: "DTS-HD HRA"
        case 0x86: "DTS-HD MA"
        case 0xA2: "DTS-HD"
        default: "Audio"
        }
    }
}

/// Big-endian reads that return zero past the end, so damaged files can't trap.
struct BigEndianBytes {
    private let storage: [UInt8]

    init(_ data: Data) {
        storage = [UInt8](data)
    }

    var count: Int { storage.count }

    func uint8(at offset: Int) -> UInt8 {
        guard offset >= 0, offset < storage.count else { return 0 }
        return storage[offset]
    }

    func uint16(at offset: Int) -> UInt16 {
        UInt16(uint8(at: offset)) << 8 | UInt16(uint8(at: offset + 1))
    }

    func uint32(at offset: Int) -> UInt32 {
        UInt32(uint16(at: offset)) << 16 | UInt32(uint16(at: offset + 2))
    }

    func string(at offset: Int, length: Int) -> String {
        guard offset >= 0, length > 0, offset + length <= storage.count else { return "" }
        return String(decoding: storage[offset..<(offset + length)], as: UTF8.self)
    }
}
