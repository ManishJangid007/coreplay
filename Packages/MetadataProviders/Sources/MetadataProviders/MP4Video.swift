import Foundation

/// Video details from MP4, M4V and QuickTime files: each track's sample
/// description, language and timing, plus the creation date and location
/// phones and cameras record.
extension MP4 {
    /// Seconds between 1904-01-01 (MP4 time zero) and 1970-01-01.
    private static let mp4EpochOffset: TimeInterval = 2_082_844_800

    static func videoInfo(_ source: ByteSource, brand: String?) throws -> VideoInfo? {
        guard let moov = try movieBox(source) else { return nil }
        let container = brand?.trimmingCharacters(in: .whitespaces) == "qt" ? "QuickTime" : "MP4"
        var info = VideoInfo(container: container)
        let headerLength = (try? Bytes.u32be(moov, 0)) == 1 ? 16 : 8
        var hasVideo = false

        for box in boxes(in: moov, from: headerLength, to: moov.count) {
            switch box.type {
            case "mvhd":
                info.duration = movieDuration(moov, box)
                info.creationDate = info.creationDate ?? creationDate(moov, box)
            case "trak":
                hasVideo = readTrack(moov, box, into: &info) || hasVideo
            case "udta":
                readUserData(moov, box, into: &info)
            case "meta":
                readQuickTimeMetadata(moov, box, into: &info)
            default:
                break
            }
        }
        guard hasVideo || !info.audioTracks.isEmpty else { return nil }
        return info
    }

    // MARK: - Movie header

    private static func creationDate(_ bytes: [UInt8], _ box: Box) -> Date? {
        let start = box.payloadStart
        guard start < bytes.count else { return nil }
        let seconds: UInt64?
        if bytes[start] == 1 {
            seconds = try? Bytes.u64be(bytes, start + 4)
        } else {
            seconds = (try? Bytes.u32be(bytes, start + 4)).map(UInt64.init)
        }
        guard let seconds, seconds > UInt64(mp4EpochOffset) else { return nil }
        let date = Date(timeIntervalSince1970: TimeInterval(seconds) - mp4EpochOffset)
        // Some encoders write "now" in odd units; ignore impossible dates.
        guard date.timeIntervalSince1970 > 0, date < Date().addingTimeInterval(86_400 * 2) else { return nil }
        return date
    }

    // MARK: - Tracks

    private struct TrackHeader {
        var handler = ""
        var timescale: UInt32 = 0
        var language: String?
        var stbl: Box?
    }

    /// Adds the track's details; `true` when it's a video track.
    private static func readTrack(_ bytes: [UInt8], _ trak: Box, into info: inout VideoInfo) -> Bool {
        var header = TrackHeader()
        let children = boxes(in: bytes, from: trak.payloadStart, to: trak.end)
        guard let mdia = children.first(where: { $0.type == "mdia" }) else { return false }
        for box in boxes(in: bytes, from: mdia.payloadStart, to: mdia.end) {
            switch box.type {
            case "mdhd":
                let start = box.payloadStart
                guard start < bytes.count else { continue }
                let version = bytes[start]
                let timescaleOffset = version == 1 ? 20 : 12
                let languageOffset = version == 1 ? 32 : 20
                header.timescale = (try? Bytes.u32be(bytes, start + timescaleOffset)) ?? 0
                if let packed = try? Bytes.u16be(bytes, start + languageOffset) {
                    header.language = packedLanguage(packed)
                }
            case "hdlr":
                header.handler = Bytes.fourCC(bytes, box.payloadStart + 8) ?? ""
            case "minf":
                header.stbl = boxes(in: bytes, from: box.payloadStart, to: box.end).first { $0.type == "stbl" }
            default:
                break
            }
        }
        guard let stbl = header.stbl else { return false }
        let tables = boxes(in: bytes, from: stbl.payloadStart, to: stbl.end)
        guard let stsd = tables.first(where: { $0.type == "stsd" }),
              let entry = boxes(in: bytes, from: stsd.payloadStart + 8, to: stsd.end).first else { return false }

        switch header.handler {
        case "vide":
            guard info.videoCodec == nil else { return true } // the first video track is the movie
            readVideoEntry(bytes, entry, into: &info)
            if let stts = tables.first(where: { $0.type == "stts" }), header.timescale > 0 {
                info.frameRate = frameRate(bytes, stts, timescale: header.timescale)
            }
            return true
        case "soun":
            info.audioTracks.append(audioTrack(bytes, entry, language: header.language))
        case "sbtl", "subt", "text", "clcp":
            let codec: String
            switch entry.type {
            case "tx3g": codec = "Timed Text"
            case "wvtt": codec = "WebVTT"
            case "stpp": codec = "TTML"
            case "c608", "c708": codec = "CEA-608"
            case "text": codec = "QuickTime Text"
            default: codec = entry.type.trimmingCharacters(in: .whitespaces)
            }
            // QuickTime "text" tracks are usually chapter titles, not subtitles.
            if header.handler == "text", entry.type == "text" { return false }
            info.subtitleTracks.append(VideoInfo.SubtitleTrack(
                codec: codec,
                language: header.language,
                isHearingImpaired: header.handler == "clcp"
            ))
        default:
            break
        }
        return false
    }

    /// The visual sample entry: codec, size, and the boxes that mark HDR.
    private static func readVideoEntry(_ bytes: [UInt8], _ entry: Box, into info: inout VideoInfo) {
        let fields = entry.payloadStart + 8 // after reserved and data reference index
        if let width = try? Bytes.u16be(bytes, fields + 16), let height = try? Bytes.u16be(bytes, fields + 18), width > 0, height > 0 {
            info.width = Int(width)
            info.height = Int(height)
        }
        var isDolbyVision = false
        switch entry.type {
        case "avc1", "avc2", "avc3", "avc4": info.videoCodec = "H.264"
        case "hvc1", "hev1": info.videoCodec = "HEVC"
        case "dvh1", "dvhe":
            info.videoCodec = "HEVC"
            isDolbyVision = true
        case "dvav", "dva1":
            info.videoCodec = "H.264"
            isDolbyVision = true
        case "dav1":
            info.videoCodec = "AV1"
            isDolbyVision = true
        case "av01": info.videoCodec = "AV1"
        case "vp09": info.videoCodec = "VP9"
        case "vp08": info.videoCodec = "VP8"
        case "mp4v": info.videoCodec = "MPEG-4"
        case "apcn", "apch", "apcs", "apco", "ap4h", "ap4x": info.videoCodec = "ProRes"
        case "jpeg", "mjpa", "mjpb": info.videoCodec = "Motion JPEG"
        case "s263", "h263": info.videoCodec = "H.263"
        default: info.videoCodec = entry.type.trimmingCharacters(in: .whitespaces).uppercased()
        }

        var transfer: UInt16?
        for child in boxes(in: bytes, from: fields + 70, to: entry.end) {
            switch child.type {
            case "dvcC", "dvvC", "dvwC":
                isDolbyVision = true
            case "colr":
                let colourType = Bytes.fourCC(bytes, child.payloadStart)
                if colourType == "nclx" || colourType == "nclc" {
                    transfer = try? Bytes.u16be(bytes, child.payloadStart + 6)
                }
            default:
                break
            }
        }
        if isDolbyVision {
            info.dynamicRange = .dolbyVision
        } else if transfer == 16 {
            info.dynamicRange = .hdr10
        } else if transfer == 18 {
            info.dynamicRange = .hlg
        } else {
            info.dynamicRange = .sdr
        }
    }

    /// The most common sample duration in `stts` gives the frame rate.
    private static func frameRate(_ bytes: [UInt8], _ stts: Box, timescale: UInt32) -> Double? {
        guard let count = try? Bytes.u32be(bytes, stts.payloadStart + 4) else { return nil }
        var best: (samples: UInt32, delta: UInt32) = (0, 0)
        var offset = stts.payloadStart + 8
        for _ in 0..<min(Int(count), 4_096) {
            guard let samples = try? Bytes.u32be(bytes, offset), let delta = try? Bytes.u32be(bytes, offset + 4) else { break }
            if samples > best.samples, delta > 0 {
                best = (samples, delta)
            }
            offset += 8
        }
        guard best.delta > 0 else { return nil }
        let rate = Double(timescale) / Double(best.delta)
        return rate.isFinite && rate > 0 && rate < 1_000 ? (rate * 1_000).rounded() / 1_000 : nil
    }

    /// An audio sample entry, with the real channel count of Dolby streams
    /// (the entry's own field usually says 2) and the Atmos flag.
    private static func audioTrack(_ bytes: [UInt8], _ entry: Box, language: String?) -> VideoInfo.AudioTrack {
        let fields = entry.payloadStart
        var channels = (try? Bytes.u16be(bytes, fields + 16)).map(Int.init)
        var isAtmos = false
        let codec: String
        switch entry.type {
        case "mp4a": codec = "AAC"
        case "ac-3": codec = "Dolby Digital"
        case "ec-3": codec = "Dolby Digital Plus"
        case "ac-4": codec = "Dolby AC-4"
        case "mlpa": codec = "Dolby TrueHD"
        case "alac": codec = "ALAC"
        case "fLaC": codec = "FLAC"
        case "Opus": codec = "Opus"
        case ".mp3": codec = "MP3"
        case "dtsc", "dtsh", "dtsl", "dtse": codec = "DTS"
        case "lpcm", "sowt", "twos", "in24", "in32", "fl32", "fl64": codec = "PCM"
        default: codec = entry.type.trimmingCharacters(in: .whitespaces).uppercased()
        }
        // Version 0 sound entries are 28 bytes; QuickTime version 1 and 2 add more.
        let version = (try? Bytes.u16be(bytes, fields + 8)) ?? 0
        if version == 2, let count = try? Bytes.u32be(bytes, fields + 40) {
            channels = Int(count)
        }
        let childrenStart = fields + 28 + (version == 1 ? 16 : version == 2 ? 36 : 0)
        for child in boxes(in: bytes, from: childrenStart, to: entry.end) {
            switch child.type {
            case "dac3":
                var reader = BitReader(bytes[child.payloadStart..<min(child.end, child.payloadStart + 3)])
                _ = reader.read(2) // fscod
                _ = reader.read(5) // bsid
                _ = reader.read(3) // bsmod
                if let acmod = reader.read(3), let lfe = reader.read(1) {
                    channels = Self.ac3Channels(acmod: Int(acmod)) + Int(lfe)
                }
            case "dec3":
                if let (count, joc) = eac3Channels(bytes[child.payloadStart..<child.end]) {
                    channels = count
                    isAtmos = joc
                }
            default:
                break
            }
        }
        return VideoInfo.AudioTrack(codec: codec, channels: channels.flatMap { $0 > 0 ? $0 : nil }, language: language, isAtmos: isAtmos)
    }

    static func ac3Channels(acmod: Int) -> Int {
        [2, 1, 2, 3, 3, 4, 4, 5][max(0, min(acmod, 7))]
    }

    /// `dec3`: channels of the first independent substream plus its
    /// dependent substreams, and whether Joint Object Coding (Atmos) is on.
    static func eac3Channels(_ payload: ArraySlice<UInt8>) -> (Int, Bool)? {
        var reader = BitReader(payload)
        guard reader.read(13) != nil, let substreams = reader.read(3) else { return nil }
        var total: Int?
        for index in 0...Int(substreams) {
            guard reader.read(2) != nil, reader.read(5) != nil, reader.read(1) != nil, reader.read(1) != nil,
                  reader.read(3) != nil, let acmod = reader.read(3), let lfe = reader.read(1),
                  reader.read(3) != nil, let dependents = reader.read(4) else { return total.map { ($0, false) } }
            var channels = ac3Channels(acmod: Int(acmod)) + Int(lfe)
            if dependents > 0 {
                guard let locations = reader.read(9) else { return nil }
                // Lc/Rc, Lrs/Rrs, Cs, Ts, Lsd/Rsd, Lw/Rw, Lvh/Rvh, Cvh, LFE2.
                let widths = [2, 2, 1, 1, 2, 2, 2, 1, 1]
                for (bit, width) in widths.enumerated() where locations & (1 << UInt32(8 - bit)) != 0 {
                    channels += width
                }
            } else {
                _ = reader.read(1)
            }
            if index == 0 {
                total = channels
            }
        }
        var joc = false
        if reader.bitsRemaining >= 16, reader.read(7) != nil, let flag = reader.read(1) {
            joc = flag == 1
        }
        return total.map { ($0, joc) }
    }

    /// ISO 639-2/T packed into three 5-bit letters.
    static func packedLanguage(_ packed: UInt16) -> String? {
        guard packed >= 0x400, packed != 0x7FFF else { return nil } // QuickTime Mac codes, or unset
        let letters = [(packed >> 10) & 0x1F, (packed >> 5) & 0x1F, packed & 0x1F].map { Character(Unicode.Scalar(UInt8($0) + 0x60)) }
        return VideoProbe.language(String(letters))
    }

    // MARK: - Metadata

    /// `udta`: iTunes-style `meta/ilst` (title, cover) and QuickTime's `©xyz` location.
    private static func readUserData(_ bytes: [UInt8], _ udta: Box, into info: inout VideoInfo) {
        for box in boxes(in: bytes, from: udta.payloadStart, to: udta.end) {
            switch box.type {
            case "meta":
                var start = box.payloadStart
                if Bytes.fourCC(bytes, start + 4) != "hdlr" {
                    start += 4
                }
                for list in boxes(in: bytes, from: start, to: box.end) where list.type == "ilst" {
                    let tags = itemList(bytes, list)
                    info.title = info.title ?? tags.title
                    info.coverArt = info.coverArt ?? tags.artwork?.data
                }
            case "\u{A9}xyz":
                // u16 length, u16 language, then the ISO 6709 string.
                if let length = try? Bytes.u16be(bytes, box.payloadStart), box.payloadStart + 4 + Int(length) <= box.end {
                    let start = box.payloadStart + 4
                    info.location = info.location ?? Text.cleaned(Text.utf8(bytes[start..<(start + Int(length))]))
                }
            default:
                break
            }
        }
    }

    /// `moov/meta` with `keys` and `ilst`: QuickTime metadata as phones write
    /// it (`com.apple.quicktime.creationdate`, `…location.ISO6709`).
    private static func readQuickTimeMetadata(_ bytes: [UInt8], _ meta: Box, into info: inout VideoInfo) {
        var start = meta.payloadStart
        if Bytes.fourCC(bytes, start + 4) != "hdlr", Bytes.fourCC(bytes, start + 4) != "keys" {
            start += 4
        }
        let children = boxes(in: bytes, from: start, to: meta.end)
        guard let keysBox = children.first(where: { $0.type == "keys" }),
              let list = children.first(where: { $0.type == "ilst" }),
              let count = try? Bytes.u32be(bytes, keysBox.payloadStart + 4) else { return }
        var keys: [String] = []
        var offset = keysBox.payloadStart + 8
        for _ in 0..<min(Int(count), 256) {
            guard let size = try? Bytes.u32be(bytes, offset), size >= 8, offset + Int(size) <= keysBox.end else { break }
            keys.append(Text.utf8(bytes[(offset + 8)..<(offset + Int(size))]))
            offset += Int(size)
        }
        for item in boxes(in: bytes, from: list.payloadStart, to: list.end) {
            // Items are named by their 1-based key index, not a four-character code.
            guard let index = try? Bytes.u32be(bytes, item.payloadStart - 4), index >= 1, Int(index) <= keys.count,
                  let data = boxes(in: bytes, from: item.payloadStart, to: item.end).first(where: { $0.type == "data" }),
                  data.payloadStart + 8 <= data.end else { continue }
            let value = Text.cleaned(Text.utf8(bytes[(data.payloadStart + 8)..<data.end]))
            switch keys[Int(index) - 1] {
            case "com.apple.quicktime.creationdate":
                if let value, let date = MediaDate.parse(value) {
                    info.creationDate = date
                }
            case "com.apple.quicktime.location.ISO6709":
                info.location = value ?? info.location
            case "com.apple.quicktime.title":
                info.title = info.title ?? value
            default:
                break
            }
        }
    }
}
