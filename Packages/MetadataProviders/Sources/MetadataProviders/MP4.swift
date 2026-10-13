import Foundation

/// MP4 / M4A / M4B: iTunes-style `moov/udta/meta/ilst` atoms, the movie
/// header for duration, and the audio sample description for the codec.
enum MP4 {
    struct Box {
        var type: String
        /// Offset of the payload (after the size and type fields).
        var payloadStart: Int
        var end: Int
    }

    /// Boxes inside `bytes[range]`, tolerating a truncated last box.
    static func boxes(in bytes: [UInt8], from start: Int, to end: Int) -> [Box] {
        var result: [Box] = []
        var position = start
        while position + 8 <= end {
            guard let size32 = try? Bytes.u32be(bytes, position), let type = Bytes.fourCC(bytes, position + 4) else { break }
            var size = Int(size32)
            var headerLength = 8
            if size == 1 {
                guard let large = try? Bytes.u64be(bytes, position + 8), large < UInt64(Int.max) else { break }
                size = Int(large)
                headerLength = 16
            } else if size == 0 {
                size = end - position
            }
            guard size >= headerLength else { break }
            let boxEnd = min(position + size, end)
            result.append(Box(type: type, payloadStart: position + headerLength, end: boxEnd))
            position += size
        }
        return result
    }

    /// The whole `moov` box (header included). The top level is walked with
    /// header-only reads: `mdat` can be gigabytes, and `moov` may come before
    /// or after it.
    static func movieBox(_ source: ByteSource) throws -> [UInt8]? {
        var position: Int64 = 0
        var steps = 0
        while position + 8 <= source.size, steps < 64 {
            let header = try source.bytes(at: position, count: 16)
            guard header.count >= 8, let type = Bytes.fourCC(header, 4) else { break }
            var size = Int64(try Bytes.u32be(header, 0))
            if size == 1 {
                guard header.count == 16 else { break }
                size = Int64(bitPattern: try Bytes.u64be(header, 8))
            } else if size == 0 {
                size = source.size - position
            }
            guard size >= 8 else { break }
            if type == "moov" {
                guard size <= Int64(TagReader.maximumArtworkBytes) * 2 else { return nil }
                return try source.bytes(at: position, count: Int(size))
            }
            position += size
            steps += 1
        }
        return nil
    }

    static func parse(_ source: ByteSource) throws -> AudioTags {
        guard let moov = try movieBox(source) else { return AudioTags() }
        var tags = AudioTags()
        let headerLength = (try? Bytes.u32be(moov, 0)) == 1 ? 16 : 8
        for box in boxes(in: moov, from: headerLength, to: moov.count) {
            switch box.type {
            case "mvhd":
                tags.duration = movieDuration(moov, box)
            case "trak":
                if tags.format == nil {
                    tags.format = audioFormat(moov, track: box)
                }
            case "udta":
                for meta in boxes(in: moov, from: box.payloadStart, to: box.end) where meta.type == "meta" {
                    // `meta` is a full box (4 bytes of version and flags) in
                    // iTunes files but not in some QuickTime-style ones.
                    var start = meta.payloadStart
                    if Bytes.fourCC(moov, start + 4) != "hdlr" {
                        start += 4
                    }
                    for list in boxes(in: moov, from: start, to: meta.end) where list.type == "ilst" {
                        tags.fillMissing(from: itemList(moov, list))
                    }
                }
            default:
                break
            }
        }
        if let duration = tags.duration, duration > 0, tags.format?.bitRate == nil, tags.format?.isLossless == false {
            tags.format?.bitRate = Int(Double(source.size) * 8 / duration)
        }
        return tags
    }

    static func movieDuration(_ bytes: [UInt8], _ box: Box) -> TimeInterval? {
        let start = box.payloadStart
        guard start < bytes.count else { return nil }
        let version = bytes[start]
        let timescale: UInt32?
        let duration: UInt64?
        if version == 1 {
            timescale = try? Bytes.u32be(bytes, start + 20)
            duration = try? Bytes.u64be(bytes, start + 24)
        } else {
            timescale = try? Bytes.u32be(bytes, start + 12)
            duration = (try? Bytes.u32be(bytes, start + 16)).map(UInt64.init)
        }
        guard let timescale, timescale > 0, let duration, duration > 0, duration != UInt64(UInt32.max) else { return nil }
        return Double(duration) / Double(timescale)
    }

    /// `trak/mdia/minf/stbl/stsd` of the first sound track.
    private static func audioFormat(_ bytes: [UInt8], track: Box) -> AudioFormatInfo? {
        guard let mdia = boxes(in: bytes, from: track.payloadStart, to: track.end).first(where: { $0.type == "mdia" }) else { return nil }
        let mdiaChildren = boxes(in: bytes, from: mdia.payloadStart, to: mdia.end)
        guard let handler = mdiaChildren.first(where: { $0.type == "hdlr" }),
              Bytes.fourCC(bytes, handler.payloadStart + 8) == "soun",
              let minf = mdiaChildren.first(where: { $0.type == "minf" }),
              let stbl = boxes(in: bytes, from: minf.payloadStart, to: minf.end).first(where: { $0.type == "stbl" }),
              let stsd = boxes(in: bytes, from: stbl.payloadStart, to: stbl.end).first(where: { $0.type == "stsd" }),
              let entry = boxes(in: bytes, from: stsd.payloadStart + 8, to: stsd.end).first else { return nil }

        // Audio sample entry: 6 reserved, 2 data reference, 8 reserved,
        // channels, sample size, 4 reserved, sample rate (16.16).
        let fields = entry.payloadStart
        let channels = (try? Bytes.u16be(bytes, fields + 16)).map(Int.init)
        var bitsPerSample = (try? Bytes.u16be(bytes, fields + 18)).map(Int.init)
        var sampleRate = (try? Bytes.u32be(bytes, fields + 24)).map { Int($0 >> 16) }

        let codec: String
        var isLossless = false
        switch entry.type {
        case "alac":
            codec = "ALAC"
            isLossless = true
            // The ALAC magic cookie has the real rate and depth (the 16.16
            // field can't hold rates above 65535 Hz).
            for child in boxes(in: bytes, from: fields + 28, to: entry.end) where child.type == "alac" {
                let config = child.payloadStart + 4
                if config + 24 <= child.end {
                    bitsPerSample = Int(bytes[config + 5])
                    sampleRate = (try? Bytes.u32be(bytes, config + 20)).map(Int.init) ?? sampleRate
                }
            }
        case "fLaC":
            codec = "FLAC"
            isLossless = true
        case "ac-3":
            codec = "Dolby Digital"
        case "ec-3":
            codec = "Dolby Digital Plus"
        case "Opus":
            codec = "Opus"
        case ".mp3":
            codec = "MP3"
        case "mp4a":
            codec = "AAC"
            bitsPerSample = nil
        default:
            codec = entry.type.trimmingCharacters(in: .whitespaces).uppercased()
        }
        return AudioFormatInfo(
            codec: codec,
            sampleRate: sampleRate.flatMap { $0 > 0 ? $0 : nil },
            channels: channels,
            bitsPerSample: isLossless ? bitsPerSample : nil,
            isLossless: isLossless
        )
    }

    /// `ilst`: one box per item, each holding `data` boxes.
    static func itemList(_ bytes: [UInt8], _ list: Box) -> AudioTags {
        var tags = AudioTags()
        var pictures: [EmbeddedArtwork] = []
        for item in boxes(in: bytes, from: list.payloadStart, to: list.end) {
            let children = boxes(in: bytes, from: item.payloadStart, to: item.end)
            let values = children.filter { $0.type == "data" }.compactMap { box -> (type: UInt32, value: ArraySlice<UInt8>)? in
                guard box.payloadStart + 8 <= box.end, let type = try? Bytes.u32be(bytes, box.payloadStart) else { return nil }
                return (type & 0x00FF_FFFF, bytes[(box.payloadStart + 8)..<box.end])
            }
            guard let first = values.first else { continue }
            let text = Text.cleaned(Text.utf8(first.value))
            switch item.type {
            case "\u{A9}nam": tags.title = text
            case "\u{A9}ART": tags.artist = text
            case "\u{A9}alb": tags.album = text
            case "aART": tags.albumArtist = text
            case "\u{A9}wrt": tags.composer = text
            case "\u{A9}gen": tags.genre = text
            case "gnre":
                if first.value.count >= 2, let index = try? Bytes.u16be(Array(first.value), 0), index > 0 {
                    tags.genre = tags.genre ?? ID3Genre.name(for: Int(index) - 1)
                }
            case "\u{A9}day": tags.year = Text.year(text)
            case "trkn", "disk":
                let pair = Array(first.value)
                let number = (try? Bytes.u16be(pair, 2)).map(Int.init).flatMap { $0 > 0 ? $0 : nil }
                let total = (try? Bytes.u16be(pair, 4)).map(Int.init).flatMap { $0 > 0 ? $0 : nil }
                if item.type == "trkn" {
                    tags.trackNumber = number
                    tags.trackCount = total
                } else {
                    tags.discNumber = number
                    tags.discCount = total
                }
            case "cpil":
                tags.isCompilation = first.value.first.map { $0 != 0 }
            case "\u{A9}lyr": tags.lyrics = text
            case "\u{A9}cmt": tags.comment = text
            case "sonm": tags.sortTitle = text
            case "soar": tags.sortArtist = text
            case "soal": tags.sortAlbum = text
            case "soaa": tags.sortAlbumArtist = text
            case "covr":
                for value in values where !value.value.isEmpty {
                    let data = Data(value.value)
                    pictures.append(EmbeddedArtwork(data: data, mimeType: Text.imageMIMEType(data), pictureType: 3))
                }
            case "----":
                // Free-form: `mean` (reverse DNS), `name`, then `data`.
                guard let nameBox = children.first(where: { $0.type == "name" }), nameBox.payloadStart + 4 <= nameBox.end else { continue }
                let name = Text.utf8(bytes[(nameBox.payloadStart + 4)..<nameBox.end]).lowercased()
                switch name {
                case "musicbrainz track id": tags.musicBrainzRecordingID = text
                case "musicbrainz album id": tags.musicBrainzAlbumID = text
                case "musicbrainz artist id": tags.musicBrainzArtistID = text
                default: break
                }
            default:
                break
            }
        }
        tags.artwork = EmbeddedArtwork.best(of: pictures)
        return tags
    }
}
