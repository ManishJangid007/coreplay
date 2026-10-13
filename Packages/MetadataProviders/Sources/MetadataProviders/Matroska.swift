import Foundation

/// Matroska (MKV) and WebM: an EBML tree. Only the segment's `Info`,
/// `Tracks`, `Chapters` and cover-art `Attachments` are read; clusters (the
/// actual audio and video) are skipped by size, so large files cost a
/// handful of small reads.
enum Matroska {
    // Element IDs (with their length marker bits, as written in files).
    private enum ID {
        static let ebml: UInt32 = 0x1A45DFA3
        static let docType: UInt32 = 0x4282
        static let segment: UInt32 = 0x18538067
        static let seekHead: UInt32 = 0x114D9B74
        static let seek: UInt32 = 0x4DBB
        static let seekID: UInt32 = 0x53AB
        static let seekPosition: UInt32 = 0x53AC
        static let info: UInt32 = 0x1549A966
        static let timestampScale: UInt32 = 0x2AD7B1
        static let duration: UInt32 = 0x4489
        static let title: UInt32 = 0x7BA9
        static let dateUTC: UInt32 = 0x4461
        static let tracks: UInt32 = 0x1654AE6B
        static let trackEntry: UInt32 = 0xAE
        static let trackType: UInt32 = 0x83
        static let flagDefault: UInt32 = 0x88
        static let flagForced: UInt32 = 0x55AA
        static let flagHearingImpaired: UInt32 = 0x55AB
        static let name: UInt32 = 0x536E
        static let language: UInt32 = 0x22B59C
        static let languageBCP47: UInt32 = 0x22B59D
        static let codecID: UInt32 = 0x86
        static let codecPrivate: UInt32 = 0x63A2
        static let defaultDuration: UInt32 = 0x23E383
        static let video: UInt32 = 0xE0
        static let pixelWidth: UInt32 = 0xB0
        static let pixelHeight: UInt32 = 0xBA
        static let colour: UInt32 = 0x55B0
        static let transferCharacteristics: UInt32 = 0x55BA
        static let audio: UInt32 = 0xE1
        static let channels: UInt32 = 0x9F
        static let blockAdditionMapping: UInt32 = 0x41E4
        static let blockAddIDType: UInt32 = 0x41E7
        static let chapters: UInt32 = 0x1043A770
        static let editionEntry: UInt32 = 0x45B9
        static let chapterAtom: UInt32 = 0xB6
        static let attachments: UInt32 = 0x1941A469
        static let attachedFile: UInt32 = 0x61A7
        static let fileName: UInt32 = 0x466E
        static let fileMediaType: UInt32 = 0x4660
        static let fileData: UInt32 = 0x465C
        static let cluster: UInt32 = 0x1F43B675
    }

    struct Element {
        var id: UInt32
        /// `nil` for "unknown size" (live recordings).
        var size: Int64?
        var dataStart: Int64
    }

    /// Largest element read whole into memory (Info, Tracks, Chapters).
    private static let maximumElementBytes: Int64 = 8 * 1_024 * 1_024

    static func read(_ source: ByteSource) throws -> VideoInfo? {
        guard let ebml = try element(source, at: 0), ebml.id == ID.ebml, let ebmlSize = ebml.size else { return nil }
        var container = "Matroska"
        for child in children(try source.bytes(at: ebml.dataStart, count: Int(min(ebmlSize, 4_096)))) where child.id == ID.docType {
            if string(child.data) == "webm" { container = "WebM" }
        }
        let segmentPosition = ebml.dataStart + ebmlSize
        guard let segment = try element(source, at: segmentPosition), segment.id == ID.segment else { return nil }
        let segmentEnd = segment.size.map { min(segment.dataStart + $0, source.size) } ?? source.size

        var info = VideoInfo(container: container)
        var seekPositions: [UInt32: Int64] = [:]
        var seen = Set<UInt32>()
        var position = segment.dataStart
        var steps = 0
        while position < segmentEnd, steps < 512 {
            steps += 1
            guard let child = try element(source, at: position) else { break }
            if child.id == ID.cluster { break } // media data: everything we need comes before it
            guard let size = child.size else { break }
            try read(child, size: size, source: source, into: &info, seekPositions: &seekPositions, segmentStart: segment.dataStart)
            seen.insert(child.id)
            position = child.dataStart + size
        }
        // Elements the writer put after the clusters, found through the SeekHead.
        for id in [ID.info, ID.tracks, ID.chapters, ID.attachments] where !seen.contains(id) {
            guard let target = seekPositions[id], target < source.size,
                  let child = try element(source, at: target), child.id == id, let size = child.size else { continue }
            try read(child, size: size, source: source, into: &info, seekPositions: &seekPositions, segmentStart: segment.dataStart)
        }
        guard info.videoCodec != nil || !info.audioTracks.isEmpty else { return nil }
        return info
    }

    private static func read(
        _ element: Element,
        size: Int64,
        source: ByteSource,
        into info: inout VideoInfo,
        seekPositions: inout [UInt32: Int64],
        segmentStart: Int64
    ) throws {
        switch element.id {
        case ID.seekHead:
            guard size <= maximumElementBytes else { return }
            for seek in children(try source.bytes(at: element.dataStart, count: Int(size))) where seek.id == ID.seek {
                var target: UInt32?
                var offset: Int64?
                for field in children(seek.data) {
                    if field.id == ID.seekID { target = UInt32(truncatingIfNeeded: unsigned(field.data)) }
                    if field.id == ID.seekPosition { offset = Int64(truncatingIfNeeded: unsigned(field.data)) }
                }
                if let target, let offset, seekPositions[target] == nil {
                    seekPositions[target] = segmentStart + offset
                }
            }
        case ID.info:
            guard size <= maximumElementBytes else { return }
            readInfo(try source.bytes(at: element.dataStart, count: Int(size)), into: &info)
        case ID.tracks:
            guard size <= maximumElementBytes else { return }
            for entry in children(try source.bytes(at: element.dataStart, count: Int(size))) where entry.id == ID.trackEntry {
                readTrack(entry.data, into: &info)
            }
        case ID.chapters:
            guard size <= maximumElementBytes else { return }
            var count = 0
            for edition in children(try source.bytes(at: element.dataStart, count: Int(size))) where edition.id == ID.editionEntry {
                count = max(count, children(edition.data).count { $0.id == ID.chapterAtom })
            }
            info.chapterCount = count > 0 ? count : nil
        case ID.attachments:
            if info.coverArt == nil {
                info.coverArt = try coverArt(source, attachmentsStart: element.dataStart, end: element.dataStart + size)
            }
        default:
            break
        }
    }

    private static func readInfo(_ bytes: [UInt8], into info: inout VideoInfo) {
        var scale: UInt64 = 1_000_000
        var duration: Double?
        for field in children(bytes) {
            switch field.id {
            case ID.timestampScale:
                let value = unsigned(field.data)
                if value > 0 { scale = value }
            case ID.duration:
                duration = float(field.data)
            case ID.title:
                info.title = Text.cleaned(string(field.data))
            case ID.dateUTC:
                // Signed nanoseconds since 2001-01-01, the reference date.
                let nanoseconds = Int64(bitPattern: unsigned(field.data))
                if nanoseconds != 0 {
                    info.creationDate = Date(timeIntervalSinceReferenceDate: Double(nanoseconds) / 1_000_000_000)
                }
            default:
                break
            }
        }
        if let duration, duration > 0, duration.isFinite {
            info.duration = duration * Double(scale) / 1_000_000_000
        }
    }

    private static func readTrack(_ bytes: ArraySlice<UInt8>, into info: inout VideoInfo) {
        var type: UInt64 = 0
        var codecID = ""
        var codecPrivate: ArraySlice<UInt8> = []
        var name: String?
        var language: String? = "eng" // Matroska's default
        var bcp47: String?
        var isDefault = true
        var isForced = false
        var isHearingImpaired = false
        var width: Int?
        var height: Int?
        var channels: Int?
        var frameDuration: UInt64?
        var transfer: UInt64?
        var isDolbyVision = false
        var isHDR10Plus = false

        for field in children(bytes) {
            switch field.id {
            case ID.trackType: type = unsigned(field.data)
            case ID.codecID: codecID = string(field.data)
            case ID.codecPrivate: codecPrivate = field.data
            case ID.name: name = Text.cleaned(string(field.data))
            case ID.language: language = string(field.data)
            case ID.languageBCP47: bcp47 = string(field.data)
            case ID.flagDefault: isDefault = unsigned(field.data) != 0
            case ID.flagForced: isForced = unsigned(field.data) != 0
            case ID.flagHearingImpaired: isHearingImpaired = unsigned(field.data) != 0
            case ID.defaultDuration: frameDuration = unsigned(field.data)
            case ID.video:
                for video in children(field.data) {
                    switch video.id {
                    case ID.pixelWidth: width = Int(truncatingIfNeeded: unsigned(video.data))
                    case ID.pixelHeight: height = Int(truncatingIfNeeded: unsigned(video.data))
                    case ID.colour:
                        for colour in children(video.data) where colour.id == ID.transferCharacteristics {
                            transfer = unsigned(colour.data)
                        }
                    default: break
                    }
                }
            case ID.audio:
                for audio in children(field.data) where audio.id == ID.channels {
                    channels = Int(truncatingIfNeeded: unsigned(audio.data))
                }
            case ID.blockAdditionMapping:
                for mapping in children(field.data) where mapping.id == ID.blockAddIDType {
                    switch unsigned(mapping.data) {
                    case 0x6476_6343, 0x6476_7643, 0x6476_7743: isDolbyVision = true // dvcC, dvvC, dvwC
                    case 4: isHDR10Plus = true // ITU-T T.35 dynamic metadata
                    default: break
                    }
                }
            default:
                break
            }
        }
        let trackLanguage = VideoProbe.language(bcp47 ?? language)
        switch type {
        case 1 where info.videoCodec == nil:
            info.videoCodec = videoCodec(codecID, codecPrivate: codecPrivate)
            info.width = width
            info.height = height
            if let frameDuration, frameDuration > 0 {
                info.frameRate = (1_000_000_000 / Double(frameDuration) * 1_000).rounded() / 1_000
            }
            if isDolbyVision {
                info.dynamicRange = .dolbyVision
            } else if isHDR10Plus {
                info.dynamicRange = .hdr10Plus
            } else if transfer == 16 {
                info.dynamicRange = .hdr10
            } else if transfer == 18 {
                info.dynamicRange = .hlg
            } else {
                info.dynamicRange = .sdr
            }
        case 2:
            let codec = audioCodec(codecID)
            info.audioTracks.append(VideoInfo.AudioTrack(
                codec: codec,
                channels: channels,
                language: trackLanguage,
                title: name,
                isAtmos: VideoProbe.namesAtmos(name) && (codec.hasPrefix("Dolby")),
                isDefault: isDefault
            ))
        case 17:
            info.subtitleTracks.append(VideoInfo.SubtitleTrack(
                codec: subtitleCodec(codecID),
                language: trackLanguage,
                title: name,
                isForced: isForced || name?.range(of: "forced", options: .caseInsensitive) != nil,
                isHearingImpaired: isHearingImpaired || name.map { $0.range(of: "SDH") != nil || $0.range(of: "CC") != nil } == true
            ))
        default:
            break
        }
    }

    /// The first attached image named like a cover ("cover.jpg", "cover_land.png").
    private static func coverArt(_ source: ByteSource, attachmentsStart: Int64, end: Int64) throws -> Data? {
        var position = attachmentsStart
        var best: (priority: Int, offset: Int64, size: Int64)?
        var steps = 0
        while position < end, steps < 256 {
            steps += 1
            guard let file = try element(source, at: position), let fileSize = file.size else { break }
            defer { position = file.dataStart + fileSize }
            guard file.id == ID.attachedFile else { continue }
            var fileName = ""
            var mediaType = ""
            var data: (Int64, Int64)?
            var inner = file.dataStart
            let fileEnd = file.dataStart + fileSize
            while inner < fileEnd {
                guard let field = try element(source, at: inner), let fieldSize = field.size else { break }
                switch field.id {
                case ID.fileName where fieldSize < 1_024:
                    fileName = string(try source.bytes(at: field.dataStart, count: Int(fieldSize))[...]).lowercased()
                case ID.fileMediaType where fieldSize < 256:
                    mediaType = string(try source.bytes(at: field.dataStart, count: Int(fieldSize))[...]).lowercased()
                case ID.fileData:
                    data = (field.dataStart, fieldSize)
                default:
                    break
                }
                inner = field.dataStart + fieldSize
            }
            guard mediaType.hasPrefix("image/") || fileName.hasSuffix(".jpg") || fileName.hasSuffix(".jpeg") || fileName.hasSuffix(".png"),
                  let (offset, size) = data, size > 0, size <= Int64(TagReader.maximumArtworkBytes) else { continue }
            // Matroska's convention: cover.jpg (portrait) beats small_cover and cover_land.
            let priority = fileName.hasPrefix("cover.") ? 0 : fileName.hasPrefix("cover") ? 1 : fileName.contains("cover") ? 2 : 3
            if priority < 3, best == nil || priority < best!.priority {
                best = (priority, offset, size)
            }
        }
        guard let best else { return nil }
        let data = try source.read(at: best.offset, count: Int(best.size))
        return data.count == Int(best.size) ? data : nil
    }

    // MARK: - Codecs

    static func videoCodec(_ id: String, codecPrivate: ArraySlice<UInt8>) -> String {
        switch id {
        case "V_MPEG4/ISO/AVC": return "H.264"
        case "V_MPEGH/ISO/HEVC": return "HEVC"
        case "V_AV1": return "AV1"
        case "V_VP9": return "VP9"
        case "V_VP8": return "VP8"
        case "V_MPEG2": return "MPEG-2"
        case "V_MPEG1": return "MPEG-1"
        case "V_MPEG4/ISO/ASP", "V_MPEG4/ISO/SP", "V_MPEG4/ISO/AP": return "MPEG-4"
        case "V_THEORA": return "Theora"
        case "V_PRORES": return "ProRes"
        case "V_FFV1": return "FFV1"
        case "V_MS/VFW/FOURCC":
            // BITMAPINFOHEADER: biCompression at offset 16.
            let header = Array(codecPrivate)
            if let fourCC = Bytes.fourCC(header, 16) {
                return AVI.videoCodec(fourCC: fourCC)
            }
            return "Video for Windows"
        default:
            if id.hasPrefix("V_REAL") { return "RealVideo" }
            return id.hasPrefix("V_") ? String(id.dropFirst(2)) : id
        }
    }

    static func audioCodec(_ id: String) -> String {
        switch id {
        case "A_AC3", "A_AC3/BSID9", "A_AC3/BSID10": return "Dolby Digital"
        case "A_EAC3": return "Dolby Digital Plus"
        case "A_TRUEHD", "A_MLP": return "Dolby TrueHD"
        case "A_DTS": return "DTS"
        case "A_DTS/EXPRESS", "A_DTS/LOSSLESS": return "DTS-HD"
        case "A_FLAC": return "FLAC"
        case "A_OPUS": return "Opus"
        case "A_VORBIS": return "Vorbis"
        case "A_MPEG/L3": return "MP3"
        case "A_MPEG/L2": return "MP2"
        case "A_ALAC": return "ALAC"
        default:
            if id.hasPrefix("A_AAC") { return "AAC" }
            if id.hasPrefix("A_PCM") { return "PCM" }
            if id.hasPrefix("A_REAL") { return "RealAudio" }
            return id.hasPrefix("A_") ? String(id.dropFirst(2)) : id
        }
    }

    static func subtitleCodec(_ id: String) -> String {
        switch id {
        case "S_TEXT/UTF8", "S_TEXT/ASCII": return "SRT"
        case "S_TEXT/SSA", "S_TEXT/ASS", "S_SSA", "S_ASS": return "ASS"
        case "S_TEXT/WEBVTT": return "WebVTT"
        case "S_HDMV/PGS": return "PGS"
        case "S_VOBSUB": return "VobSub"
        case "S_DVBSUB": return "DVB"
        case "S_HDMV/TEXTST": return "Text"
        default: return id.hasPrefix("S_") ? String(id.dropFirst(2)) : id
        }
    }

    // MARK: - EBML

    /// An element header at `position` in the source.
    static func element(_ source: ByteSource, at position: Int64) throws -> Element? {
        let header = try source.bytes(at: position, count: 12)
        var index = 0
        guard let id = elementID(header, &index), let size = elementSize(header, &index) else { return nil }
        return Element(id: id, size: size, dataStart: position + Int64(index))
    }

    struct Child {
        var id: UInt32
        var data: ArraySlice<UInt8>
    }

    /// The child elements of an in-memory element body.
    static func children(_ bytes: [UInt8]) -> [Child] {
        children(bytes[...])
    }

    static func children(_ bytes: ArraySlice<UInt8>) -> [Child] {
        var result: [Child] = []
        let base = Array(bytes)
        var index = 0
        while index < base.count {
            guard let id = elementID(base, &index), let size = elementSize(base, &index) else { break }
            let length = Int(min(size ?? Int64(base.count - index), Int64(base.count - index)))
            guard length >= 0 else { break }
            result.append(Child(id: id, data: base[index..<(index + length)]))
            index += length
        }
        return result
    }

    /// An ID keeps its length-marker bits.
    private static func elementID(_ bytes: [UInt8], _ index: inout Int) -> UInt32? {
        guard index < bytes.count else { return nil }
        let first = bytes[index]
        let length = first.leadingZeroBitCount + 1
        guard length <= 4, index + length <= bytes.count else { return nil }
        var value: UInt32 = 0
        for offset in 0..<length {
            value = value << 8 | UInt32(bytes[index + offset])
        }
        index += length
        return value
    }

    /// A size drops its marker bit; all ones means "unknown" (`.some(nil)`).
    private static func elementSize(_ bytes: [UInt8], _ index: inout Int) -> Int64?? {
        guard index < bytes.count else { return nil }
        let first = bytes[index]
        let length = first.leadingZeroBitCount + 1
        guard length <= 8, index + length <= bytes.count else { return nil }
        var value = UInt64(first & (0xFF >> UInt8(length)))
        var allOnes = value == UInt64(0xFF >> UInt8(length))
        for offset in 1..<length {
            let byte = bytes[index + offset]
            value = value << 8 | UInt64(byte)
            allOnes = allOnes && byte == 0xFF
        }
        index += length
        if allOnes { return .some(nil) }
        guard value < UInt64(Int64.max) else { return nil }
        return .some(Int64(value))
    }

    static func unsigned(_ data: ArraySlice<UInt8>) -> UInt64 {
        data.prefix(8).reduce(0) { $0 << 8 | UInt64($1) }
    }

    static func float(_ data: ArraySlice<UInt8>) -> Double? {
        let value = unsigned(data)
        switch data.count {
        case 4: return Double(Float(bitPattern: UInt32(truncatingIfNeeded: value)))
        case 8: return Double(bitPattern: value)
        default: return nil
        }
    }

    static func string(_ data: ArraySlice<UInt8>) -> String {
        let trimmed = data.prefix { $0 != 0 }
        return String(decoding: trimmed, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
