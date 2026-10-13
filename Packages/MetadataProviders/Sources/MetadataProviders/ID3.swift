import Foundation

/// ID3v2.2, 2.3 and 2.4 tags (MP3, AAC, AIFF and WAV chunks) and ID3v1.
enum ID3v2 {
    /// Total size of an ID3v2 tag that starts at `header[0]` (header, body and
    /// footer), or `nil` when there's no tag.
    static func tagSize(header: [UInt8]) -> Int? {
        guard header.count >= 10, Bytes.matches(header, 0, "ID3"),
              (2...4).contains(header[3]), header[3] != 0xFF,
              let bodySize = try? Bytes.syncsafe(header, 6) else { return nil }
        let hasFooter = header[3] == 4 && header[5] & 0x10 != 0
        return 10 + bodySize + (hasFooter ? 10 : 0)
    }

    /// Parses a complete tag, header included.
    static func parse(_ tag: [UInt8]) -> AudioTags? {
        guard tag.count >= 10, Bytes.matches(tag, 0, "ID3") else { return nil }
        let major = tag[3]
        guard (2...4).contains(major), let declared = try? Bytes.syncsafe(tag, 6) else { return nil }
        let flags = tag[5]
        var body = Array(tag[10..<min(tag.count, 10 + declared)])
        if flags & 0x80 != 0, major < 4 {
            body = removeUnsynchronisation(body)
        }

        var position = 0
        if flags & 0x40 != 0, major >= 3 {
            if major == 3, let extendedSize = try? Bytes.u32be(body, 0) {
                position = 4 + Int(extendedSize)
            } else if major == 4, let extendedSize = try? Bytes.syncsafe(body, 0) {
                position = extendedSize
            }
        }

        var collector = FrameCollector()
        while position < body.count {
            if major == 2 {
                guard position + 6 <= body.count, body[position] != 0 else { break }
                let id = Bytes.ascii(body[position..<(position + 3)])
                let size = Int((try? Bytes.u24be(body, position + 3)) ?? 0)
                position += 6
                guard size > 0, position + size <= body.count else { break }
                collector.handle(id: id, data: Array(body[position..<(position + size)]), version: 2)
                position += size
            } else {
                guard position + 10 <= body.count, body[position] != 0 else { break }
                let id = Bytes.ascii(body[position..<(position + 4)])
                guard id.allSatisfy({ $0.isUppercase || $0.isNumber }) else { break }
                let size = frameSize(body, position, major: major)
                let statusFlags = body[position + 9]
                position += 10
                guard size > 0, position + size <= body.count else { break }
                var data = Array(body[position..<(position + size)])
                position += size
                if major == 3 {
                    // Compressed or encrypted frames aren't worth decoding for tags.
                    if statusFlags & 0xC0 != 0 { continue }
                    if statusFlags & 0x20 != 0, !data.isEmpty { data.removeFirst() }
                } else {
                    if statusFlags & 0x0C != 0 { continue }
                    var skip = 0
                    if statusFlags & 0x40 != 0 { skip += 1 }
                    if statusFlags & 0x01 != 0 { skip += 4 }
                    data = Array(data.dropFirst(skip))
                    if statusFlags & 0x02 != 0 {
                        data = removeUnsynchronisation(data)
                    }
                }
                collector.handle(id: id, data: data, version: Int(major))
            }
        }
        return collector.tags()
    }

    /// v2.4 frame sizes are syncsafe, except in files from encoders (older
    /// iTunes among them) that wrote plain integers. Pick whichever lands on
    /// the next frame.
    private static func frameSize(_ body: [UInt8], _ position: Int, major: UInt8) -> Int {
        let plain = Int((try? Bytes.u32be(body, position + 4)) ?? 0)
        guard major == 4 else { return plain }
        let syncsafe = (try? Bytes.syncsafe(body, position + 4)) ?? 0
        let sizeBytes = body[(position + 4)..<(position + 8)]
        if sizeBytes.contains(where: { $0 & 0x80 != 0 }) {
            return plain
        }
        if syncsafe != plain, !looksLikeFrameStart(body, position + 10 + syncsafe),
           looksLikeFrameStart(body, position + 10 + plain) {
            return plain
        }
        return syncsafe
    }

    private static func looksLikeFrameStart(_ body: [UInt8], _ index: Int) -> Bool {
        if index == body.count { return true }
        guard index + 4 <= body.count else { return false }
        if body[index] == 0 { return true } // padding
        return body[index..<(index + 4)].allSatisfy { ($0 >= 0x41 && $0 <= 0x5A) || ($0 >= 0x30 && $0 <= 0x39) }
    }

    static func removeUnsynchronisation(_ bytes: [UInt8]) -> [UInt8] {
        var result: [UInt8] = []
        result.reserveCapacity(bytes.count)
        var index = 0
        while index < bytes.count {
            let byte = bytes[index]
            result.append(byte)
            if byte == 0xFF, index + 1 < bytes.count, bytes[index + 1] == 0x00 {
                index += 2
            } else {
                index += 1
            }
        }
        return result
    }
}

/// Collects ID3v2 frames into `AudioTags`.
private struct FrameCollector {
    private var text: [String: String] = [:]
    private var userText: [String: String] = [:]
    private var pictures: [EmbeddedArtwork] = []
    private var lyrics: String?
    private var comment: String?
    private var lengthMilliseconds: Int?
    private var recordingID: String?

    mutating func handle(id: String, data: [UInt8], version: Int) {
        let id = version == 2 ? (Self.v22ToV24[id] ?? id) : id
        switch id {
        case "APIC":
            if let picture = Self.picture(data, isV22: version == 2) {
                pictures.append(picture)
            }
        case "USLT":
            lyrics = lyrics ?? Self.languageText(data)
        case "COMM":
            if comment == nil, let value = Self.languageText(data), !value.isEmpty {
                comment = value
            }
        case "TXXX":
            if let (key, value) = Self.userText(data) {
                userText[key.lowercased()] = value
            }
        case "UFID":
            if let (owner, identifier) = Self.uniqueFileIdentifier(data), owner == "http://musicbrainz.org" {
                recordingID = identifier
            }
        case "TLEN":
            if let value = Self.textValues(data).first, let milliseconds = Int(value), milliseconds > 0 {
                lengthMilliseconds = milliseconds
            }
        default:
            if id.hasPrefix("T"), text[id] == nil, let value = Self.textValues(data).first {
                text[id] = value
            }
        }
    }

    func tags() -> AudioTags {
        var tags = AudioTags()
        tags.title = Text.cleaned(text["TIT2"])
        tags.artist = Text.cleaned(text["TPE1"])
        tags.album = Text.cleaned(text["TALB"])
        tags.albumArtist = Text.cleaned(text["TPE2"]) ?? Text.cleaned(userText["album artist"] ?? userText["albumartist"])
        tags.composer = Text.cleaned(text["TCOM"])
        tags.genre = ID3Genre.resolve(text["TCON"])
        tags.year = Text.year(text["TDRC"]) ?? Text.year(text["TYER"]) ?? Text.year(text["TDOR"]) ?? Text.year(text["TORY"])
        (tags.trackNumber, tags.trackCount) = Text.numberPair(text["TRCK"])
        (tags.discNumber, tags.discCount) = Text.numberPair(text["TPOS"])
        tags.isCompilation = Text.bool(text["TCMP"])
        tags.sortTitle = Text.cleaned(text["TSOT"])
        tags.sortArtist = Text.cleaned(text["TSOP"])
        tags.sortAlbum = Text.cleaned(text["TSOA"])
        tags.sortAlbumArtist = Text.cleaned(text["TSO2"])
        tags.lyrics = Text.cleaned(lyrics)
        tags.comment = Text.cleaned(comment)
        tags.musicBrainzAlbumID = Text.cleaned(userText["musicbrainz album id"])
        tags.musicBrainzArtistID = Text.cleaned(userText["musicbrainz artist id"])
        tags.musicBrainzRecordingID = Text.cleaned(recordingID)
        tags.artwork = EmbeddedArtwork.best(of: pictures)
        if let lengthMilliseconds {
            tags.duration = TimeInterval(lengthMilliseconds) / 1000
        }
        return tags
    }

    // MARK: Frame bodies

    /// Decodes `bytes` in an ID3 text encoding (0 Latin-1, 1 UTF-16 with BOM,
    /// 2 UTF-16BE, 3 UTF-8).
    static func decode(_ bytes: ArraySlice<UInt8>, encoding: UInt8) -> String {
        switch encoding {
        case 1: Text.utf16(bytes, bigEndian: false)
        case 2: Text.utf16(bytes, bigEndian: true)
        case 3: Text.utf8(bytes)
        default: Text.latin1(bytes)
        }
    }

    /// Splits at the encoding's terminator (one NUL, or two aligned NULs for UTF-16).
    static func split(_ bytes: ArraySlice<UInt8>, encoding: UInt8) -> (ArraySlice<UInt8>, ArraySlice<UInt8>) {
        let wide = encoding == 1 || encoding == 2
        var index = bytes.startIndex
        while index < bytes.endIndex {
            if wide {
                if index + 1 < bytes.endIndex, bytes[index] == 0, bytes[index + 1] == 0 {
                    return (bytes[bytes.startIndex..<index], bytes[(index + 2)...])
                }
                index += 2
            } else {
                if bytes[index] == 0 {
                    return (bytes[bytes.startIndex..<index], bytes[(index + 1)...])
                }
                index += 1
            }
        }
        return (bytes, [])
    }

    /// Text frames: an encoding byte, then one value (v2.3) or NUL-separated values (v2.4).
    static func textValues(_ data: [UInt8]) -> [String] {
        guard let encoding = data.first else { return [] }
        var rest = data.dropFirst()
        var values: [String] = []
        while !rest.isEmpty {
            let (value, remainder) = split(rest, encoding: encoding)
            if let cleaned = Text.cleaned(decode(value, encoding: encoding)) {
                values.append(cleaned)
            }
            rest = remainder
        }
        return values
    }

    /// USLT / COMM: encoding, 3-byte language, description, text.
    static func languageText(_ data: [UInt8]) -> String? {
        guard data.count > 4, let encoding = data.first else { return nil }
        let (_, text) = split(data.dropFirst(4), encoding: encoding)
        return Text.cleaned(decode(text, encoding: encoding))
    }

    /// TXXX: encoding, description, value.
    static func userText(_ data: [UInt8]) -> (String, String)? {
        guard let encoding = data.first else { return nil }
        let (description, value) = split(data.dropFirst(), encoding: encoding)
        guard let key = Text.cleaned(decode(description, encoding: encoding)),
              let text = Text.cleaned(decode(value, encoding: encoding)) else { return nil }
        return (key, text)
    }

    /// UFID: Latin-1 owner, NUL, binary identifier (ASCII for MusicBrainz).
    static func uniqueFileIdentifier(_ data: [UInt8]) -> (String, String)? {
        let (owner, identifier) = split(data[...], encoding: 0)
        guard !identifier.isEmpty else { return nil }
        return (Text.latin1(owner), Text.latin1(identifier))
    }

    /// APIC (v2.3/2.4): encoding, MIME, type, description, data.
    /// PIC (v2.2): encoding, 3-letter format, type, description, data.
    static func picture(_ data: [UInt8], isV22: Bool) -> EmbeddedArtwork? {
        guard let encoding = data.first, data.count > 4 else { return nil }
        var mimeType: String?
        var rest: ArraySlice<UInt8>
        if isV22 {
            let format = Bytes.ascii(data[1..<4]).uppercased()
            mimeType = format == "PNG" ? "image/png" : "image/jpeg"
            rest = data[4...]
        } else {
            let (mime, remainder) = split(data.dropFirst(), encoding: 0)
            mimeType = Text.cleaned(Text.latin1(mime))
            rest = remainder
        }
        guard let pictureType = rest.first else { return nil }
        let (_, imageBytes) = split(rest.dropFirst(), encoding: encoding)
        guard !imageBytes.isEmpty else { return nil }
        let imageData = Data(imageBytes)
        return EmbeddedArtwork(data: imageData, mimeType: Text.imageMIMEType(imageData) ?? mimeType, pictureType: Int(pictureType))
    }

    /// ID3v2.2 used three-letter frame IDs.
    static let v22ToV24: [String: String] = [
        "TT2": "TIT2", "TP1": "TPE1", "TAL": "TALB", "TP2": "TPE2", "TCM": "TCOM",
        "TCO": "TCON", "TYE": "TYER", "TRK": "TRCK", "TPA": "TPOS", "TCP": "TCMP",
        "TST": "TSOT", "TSP": "TSOP", "TSA": "TSOA", "TS2": "TSO2", "TLE": "TLEN",
        "PIC": "APIC", "ULT": "USLT", "COM": "COMM", "TXX": "TXXX", "UFI": "UFID",
        "TOR": "TORY",
    ]
}

/// ID3v1 / ID3v1.1: 128 bytes at the very end of the file.
enum ID3v1 {
    static func parse(_ bytes: [UInt8]) -> AudioTags? {
        guard bytes.count == 128, Bytes.matches(bytes, 0, "TAG") else { return nil }
        func field(_ range: Range<Int>) -> String? {
            let slice = bytes[range]
            let end = slice.firstIndex(of: 0) ?? slice.endIndex
            return Text.cleaned(Text.latin1(slice[slice.startIndex..<end]))
        }
        var tags = AudioTags()
        tags.title = field(3..<33)
        tags.artist = field(33..<63)
        tags.album = field(63..<93)
        tags.year = Text.year(field(93..<97))
        if bytes[125] == 0, bytes[126] != 0 {
            tags.trackNumber = Int(bytes[126])
            tags.comment = field(97..<125)
        } else {
            tags.comment = field(97..<127)
        }
        tags.genre = ID3Genre.name(for: Int(bytes[127]))
        return tags.hasDescriptiveTags || tags.genre != nil ? tags : nil
    }
}

/// The ID3v1 genre list (with Winamp's extensions), used by ID3v1, ID3v2
/// "(17)" references and the MP4 `gnre` atom.
enum ID3Genre {
    static func name(for index: Int) -> String? {
        names.indices.contains(index) ? names[index] : nil
    }

    /// "Rock", "(17)", "17", "(17)Rock" or "(RX)" → a genre name.
    static func resolve(_ raw: String?) -> String? {
        guard var value = Text.cleaned(raw) else { return nil }
        while value.hasPrefix("(") {
            guard let close = value.firstIndex(of: ")") else { break }
            let inner = String(value[value.index(after: value.startIndex)..<close])
            let rest = String(value[value.index(after: close)...])
            if let restName = Text.cleaned(rest) {
                value = restName
                continue
            }
            switch inner {
            case "RX": return "Remix"
            case "CR": return "Cover"
            default:
                if let number = Int(inner) { return name(for: number) }
                return Text.cleaned(inner)
            }
        }
        if let number = Int(value) {
            return name(for: number)
        }
        return value
    }

    static let names: [String] = [
        "Blues", "Classic Rock", "Country", "Dance", "Disco", "Funk", "Grunge", "Hip-Hop",
        "Jazz", "Metal", "New Age", "Oldies", "Other", "Pop", "R&B", "Rap", "Reggae", "Rock",
        "Techno", "Industrial", "Alternative", "Ska", "Death Metal", "Pranks", "Soundtrack",
        "Euro-Techno", "Ambient", "Trip-Hop", "Vocal", "Jazz+Funk", "Fusion", "Trance",
        "Classical", "Instrumental", "Acid", "House", "Game", "Sound Clip", "Gospel", "Noise",
        "Alternative Rock", "Bass", "Soul", "Punk", "Space", "Meditative", "Instrumental Pop",
        "Instrumental Rock", "Ethnic", "Gothic", "Darkwave", "Techno-Industrial", "Electronic",
        "Pop-Folk", "Eurodance", "Dream", "Southern Rock", "Comedy", "Cult", "Gangsta", "Top 40",
        "Christian Rap", "Pop/Funk", "Jungle", "Native American", "Cabaret", "New Wave",
        "Psychedelic", "Rave", "Showtunes", "Trailer", "Lo-Fi", "Tribal", "Acid Punk",
        "Acid Jazz", "Polka", "Retro", "Musical", "Rock & Roll", "Hard Rock", "Folk",
        "Folk-Rock", "National Folk", "Swing", "Fast Fusion", "Bebop", "Latin", "Revival",
        "Celtic", "Bluegrass", "Avantgarde", "Gothic Rock", "Progressive Rock",
        "Psychedelic Rock", "Symphonic Rock", "Slow Rock", "Big Band", "Chorus",
        "Easy Listening", "Acoustic", "Humour", "Speech", "Chanson", "Opera", "Chamber Music",
        "Sonata", "Symphony", "Booty Bass", "Primus", "Porn Groove", "Satire", "Slow Jam",
        "Club", "Tango", "Samba", "Folklore", "Ballad", "Power Ballad", "Rhythmic Soul",
        "Freestyle", "Duet", "Punk Rock", "Drum Solo", "A Cappella", "Euro-House", "Dance Hall",
        "Goa", "Drum & Bass", "Club-House", "Hardcore", "Terror", "Indie", "Britpop",
        "Afro-Punk", "Polsk Punk", "Beat", "Christian Gangsta Rap", "Heavy Metal", "Black Metal",
        "Crossover", "Contemporary Christian", "Christian Rock", "Merengue", "Salsa",
        "Thrash Metal", "Anime", "J-Pop", "Synthpop", "Abstract", "Art Rock", "Baroque",
        "Bhangra", "Big Beat", "Breakbeat", "Chillout", "Downtempo", "Dub", "EBM", "Eclectic",
        "Electro", "Electroclash", "Emo", "Experimental", "Garage", "Global", "IDM", "Illbient",
        "Industro-Goth", "Jam Band", "Krautrock", "Leftfield", "Lounge", "Math Rock",
        "New Romantic", "Nu-Breakz", "Post-Punk", "Post-Rock", "Psytrance", "Shoegaze",
        "Space Rock", "Trop Rock", "World Music", "Neoclassical", "Audiobook", "Audio Theatre",
        "Neue Deutsche Welle", "Podcast", "Indie Rock", "G-Funk", "Dubstep", "Garage Rock",
        "Psybient",
    ]
}
