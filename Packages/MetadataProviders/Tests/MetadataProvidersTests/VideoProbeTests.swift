import Foundation
import Testing
@testable import MetadataProviders

/// Builds MP4, Matroska and AVI headers byte by byte.
private enum VideoFixtures {
    typealias F = Fixtures

    // MARK: MP4

    static func box(_ type: String, _ payload: [UInt8]) -> [UInt8] {
        F.join(F.be32(8 + payload.count), F.latin1(type), payload)
    }

    static func fullBox(_ type: String, version: UInt8 = 0, _ payload: [UInt8]) -> [UInt8] {
        box(type, F.join([version, 0, 0, 0], payload))
    }

    static func packedLanguage(_ code: String) -> [UInt8] {
        let letters = Array(code.utf8).map { Int($0) - 0x60 }
        return F.be16(letters[0] << 10 | letters[1] << 5 | letters[2])
    }

    static func track(handler: String, language: String, timescale: Int, entry: [UInt8], extraTables: [UInt8] = []) -> [UInt8] {
        let mdhd = fullBox("mdhd", F.join(F.be32(0), F.be32(0), F.be32(timescale), F.be32(timescale * 10), packedLanguage(language), F.be16(0)))
        let hdlr = fullBox("hdlr", F.join(F.be32(0), F.latin1(handler), [UInt8](repeating: 0, count: 12), [0]))
        let stsd = fullBox("stsd", F.join(F.be32(1), entry))
        let stbl = box("stbl", F.join(stsd, extraTables))
        let minf = box("minf", stbl)
        return box("trak", box("mdia", F.join(mdhd, hdlr, minf)))
    }

    static func videoEntry(_ type: String, width: Int, height: Int, children: [UInt8]) -> [UInt8] {
        let fields = F.join(
            [UInt8](repeating: 0, count: 6), F.be16(1),  // reserved, data reference index
            [UInt8](repeating: 0, count: 16),            // pre-defined and reserved
            F.be16(width), F.be16(height),
            [UInt8](repeating: 0, count: 50)             // resolution, frame count, compressor, depth
        )
        return box(type, F.join(fields, children))
    }

    static func audioEntry(_ type: String, channels: Int, children: [UInt8]) -> [UInt8] {
        let fields = F.join(
            [UInt8](repeating: 0, count: 6), F.be16(1),
            [UInt8](repeating: 0, count: 8),             // version, revision, vendor
            F.be16(channels), F.be16(16), F.be16(0), F.be16(0), F.be32(48_000 << 16)
        )
        return box(type, F.join(fields, children))
    }

    /// `dec3` for 5.1 plus a dependent substream with the rear pair (7.1), with JOC.
    static func dec3(atmos: Bool) -> [UInt8] {
        var bits = BitWriter()
        bits.write(1_536, 13) // data rate
        bits.write(0, 3)      // one independent substream
        bits.write(0, 2)      // fscod
        bits.write(16, 5)     // bsid
        bits.write(0, 1)
        bits.write(0, 1)      // asvc
        bits.write(0, 3)      // bsmod
        bits.write(7, 3)      // acmod 3/2
        bits.write(1, 1)      // LFE
        bits.write(0, 3)
        bits.write(1, 4)      // one dependent substream
        bits.write(0b010000000, 9) // Lrs/Rrs
        bits.write(0, 7)
        bits.write(atmos ? 1 : 0, 1)
        bits.write(16, 8)     // complexity index
        return box("dec3", bits.bytes)
    }

    static func quickTimeMetadata(_ items: [(String, String)]) -> [UInt8] {
        let hdlr = fullBox("hdlr", F.join(F.be32(0), F.latin1("mdta"), [UInt8](repeating: 0, count: 12), [0]))
        let keyEntries = items.map { F.join(F.be32(8 + $0.0.utf8.count), F.latin1("mdta"), F.ascii($0.0)) }
        let keys = fullBox("keys", F.join(F.be32(items.count), keyEntries.flatMap { $0 }))
        let entries = items.enumerated().map { index, item in
            F.join(F.be32(8 + 16 + item.1.utf8.count), F.be32(index + 1), box("data", F.join(F.be32(1), F.be32(0), F.ascii(item.1))))
        }
        let ilst = box("ilst", entries.flatMap { $0 })
        return box("meta", F.join(hdlr, keys, ilst))
    }

    static func mp4(creation: Int, extra: [UInt8]) -> [UInt8] {
        let mvhd = fullBox("mvhd", F.join(F.be32(creation), F.be32(creation), F.be32(600), F.be32(600 * 5_400), [UInt8](repeating: 0, count: 80)))
        let colr = box("colr", F.join(F.latin1("nclx"), F.be16(9), F.be16(16), F.be16(9), [0x80]))
        let dvcC = box("dvcC", [UInt8](repeating: 0, count: 24))
        let video = track(
            handler: "vide", language: "und", timescale: 24_000,
            entry: videoEntry("hvc1", width: 3_840, height: 2_160, children: F.join(colr, dvcC)),
            extraTables: fullBox("stts", F.join(F.be32(1), F.be32(1_000), F.be32(1_001)))
        )
        let audio = track(handler: "soun", language: "eng", timescale: 48_000, entry: audioEntry("ec-3", channels: 2, children: dec3(atmos: true)))
        let subtitles = track(handler: "sbtl", language: "fra", timescale: 1_000, entry: box("tx3g", [UInt8](repeating: 0, count: 40)))
        let moov = box("moov", F.join(mvhd, video, audio, subtitles, extra))
        let ftyp = box("ftyp", F.join(F.latin1("isom"), F.be32(0), F.latin1("isom")))
        return F.join(ftyp, box("mdat", [1, 2, 3, 4]), moov)
    }

    // MARK: Matroska

    static func ebml(_ id: UInt32, _ payload: [UInt8]) -> [UInt8] {
        var idBytes = F.be32(Int(id))
        while idBytes.first == 0 { idBytes.removeFirst() }
        let size = payload.count
        let sizeBytes: [UInt8]
        if size < 0x7F {
            sizeBytes = [0x80 | UInt8(size)]
        } else if size < 0x3FFF {
            sizeBytes = [0x40 | UInt8(size >> 8), UInt8(size & 0xFF)]
        } else {
            sizeBytes = [0x10] + Array(F.be32(size).dropFirst())
        }
        return F.join(idBytes, sizeBytes, payload)
    }

    static func uint(_ id: UInt32, _ value: Int) -> [UInt8] {
        var bytes = F.be32(value)
        while bytes.count > 1, bytes.first == 0 { bytes.removeFirst() }
        return ebml(id, bytes)
    }

    static func double(_ id: UInt32, _ value: Double) -> [UInt8] {
        let bits = value.bitPattern
        return ebml(id, (0..<8).map { UInt8(bits >> (8 * (7 - UInt64($0))) & 0xFF) })
    }

    static func text(_ id: UInt32, _ value: String) -> [UInt8] {
        ebml(id, F.ascii(value))
    }

    static func mkv(clusterBeforeTracks: Bool) -> [UInt8] {
        let header = ebml(0x1A45DFA3, F.join(text(0x4282, "matroska"), uint(0x4287, 4)))
        let info = ebml(0x1549A966, F.join(uint(0x2AD7B1, 1_000_000), double(0x4489, 7_200_000), text(0x7BA9, "A Movie")))
        let video = ebml(0xAE, F.join(
            uint(0xD7, 1), uint(0x83, 1), text(0x86, "V_MPEGH/ISO/HEVC"), uint(0x23E383, 41_708_333),
            ebml(0xE0, F.join(uint(0xB0, 3_840), uint(0xBA, 1_600), ebml(0x55B0, uint(0x55BA, 16))))
        ))
        let audio = ebml(0xAE, F.join(
            uint(0xD7, 2), uint(0x83, 2), text(0x86, "A_TRUEHD"), text(0x536E, "TrueHD Atmos 7.1"),
            text(0x22B59C, "eng"), ebml(0xE1, uint(0x9F, 8))
        ))
        let commentary = ebml(0xAE, F.join(
            uint(0xD7, 3), uint(0x83, 2), text(0x86, "A_AC3"), text(0x22B59C, "und"), uint(0x88, 0), ebml(0xE1, uint(0x9F, 2))
        ))
        let subtitles = ebml(0xAE, F.join(
            uint(0xD7, 4), uint(0x83, 17), text(0x86, "S_HDMV/PGS"), text(0x22B59C, "spa"), uint(0x55AA, 1)
        ))
        let tracks = ebml(0x1654AE6B, F.join(video, audio, commentary, subtitles))
        let attachments = ebml(0x1941A469, F.join(
            ebml(0x61A7, F.join(text(0x466E, "font.ttf"), text(0x4660, "font/ttf"), ebml(0x465C, [0, 1, 0, 0]))),
            ebml(0x61A7, F.join(text(0x466E, "cover.jpg"), text(0x4660, "image/jpeg"), ebml(0x465C, F.jpeg)))
        ))
        let cluster = ebml(0x1F43B675, F.join(uint(0xE7, 0), ebml(0xA3, [UInt8](repeating: 7, count: 64))))

        let body: [UInt8]
        if clusterBeforeTracks {
            // SeekHead → Info, Cluster, then Tracks and Attachments (found by seeking).
            let seekHeadSize = 2 * (2 + 2 + 7 + 2 + 5) + 0 // estimated; recomputed below
            _ = seekHeadSize
            func seekHead(tracksAt: Int, attachmentsAt: Int) -> [UInt8] {
                ebml(0x114D9B74, F.join(
                    ebml(0x4DBB, F.join(ebml(0x53AB, F.be32(0x1654AE6B)), ebml(0x53AC, F.be32(tracksAt)))),
                    ebml(0x4DBB, F.join(ebml(0x53AB, F.be32(0x1941A469)), ebml(0x53AC, F.be32(attachmentsAt))))
                ))
            }
            let placeholder = seekHead(tracksAt: 0, attachmentsAt: 0)
            let tracksAt = placeholder.count + info.count + cluster.count
            let attachmentsAt = tracksAt + tracks.count
            body = F.join(seekHead(tracksAt: tracksAt, attachmentsAt: attachmentsAt), info, cluster, tracks, attachments)
        } else {
            body = F.join(info, tracks, attachments, cluster)
        }
        return F.join(header, ebml(0x18538067, body))
    }

    // MARK: AVI

    static func chunk(_ id: String, _ payload: [UInt8]) -> [UInt8] {
        F.join(F.ascii(id), F.le32(payload.count), payload, payload.count % 2 == 1 ? [0] : [])
    }

    static func list(_ type: String, _ payload: [UInt8]) -> [UInt8] {
        chunk("LIST", F.join(F.ascii(type), payload))
    }

    static func avi() -> [UInt8] {
        let avih = chunk("avih", F.join(
            F.le32(40_000), F.le32(0), F.le32(0), F.le32(0x10), F.le32(1_000), F.le32(0), F.le32(2), F.le32(0),
            F.le32(720), F.le32(480), [UInt8](repeating: 0, count: 16)
        ))
        let videoHeader = chunk("strh", F.join(
            F.ascii("vids"), F.ascii("XVID"), F.le32(0), F.le16(0), F.le16(0), F.le32(0),
            F.le32(1_001), F.le32(30_000), F.le32(0), F.le32(90_000), [UInt8](repeating: 0, count: 20)
        ))
        let bitmap = chunk("strf", F.join(F.le32(40), F.le32(720), F.le32(480), F.le16(1), F.le16(24), F.ascii("XVID"), [UInt8](repeating: 0, count: 20)))
        let audioHeader = chunk("strh", F.join(F.ascii("auds"), [0, 0, 0, 0], [UInt8](repeating: 0, count: 48)))
        let wave = chunk("strf", F.join(F.le16(0x2000), F.le16(6), F.le32(48_000), F.le32(56_000), F.le16(4), F.le16(16), F.le16(0)))
        let hdrl = list("hdrl", F.join(avih, list("strl", F.join(videoHeader, bitmap)), list("strl", F.join(audioHeader, wave))))
        let movi = list("movi", [UInt8](repeating: 0, count: 32))
        let body = F.join(F.ascii("AVI "), hdrl, movi)
        return F.join(F.ascii("RIFF"), F.le32(body.count), body)
    }
}

/// Writes bit fields, most significant bit first.
private struct BitWriter {
    private(set) var bytes: [UInt8] = []
    private var bitCount = 0

    mutating func write(_ value: Int, _ width: Int) {
        for shift in stride(from: width - 1, through: 0, by: -1) {
            if bitCount % 8 == 0 { bytes.append(0) }
            if (value >> shift) & 1 == 1 {
                bytes[bytes.count - 1] |= UInt8(0x80 >> (bitCount % 8))
            }
            bitCount += 1
        }
    }
}

@Suite("Video files")
struct VideoProbeTests {
    @Test func mp4WithDolbyVisionAndAtmos() throws {
        let creation = 1_710_497_554 + 2_082_844_800
        let meta = VideoFixtures.quickTimeMetadata([
            ("com.apple.quicktime.creationdate", "2024-03-15T11:12:34+0100"),
            ("com.apple.quicktime.location.ISO6709", "+37.7858-122.4064+010.000/"),
        ])
        let info = try #require(try VideoProbe.read(DataByteSource(VideoFixtures.mp4(creation: creation, extra: meta))))
        #expect(info.container == "MP4")
        #expect(info.duration == 5_400)
        #expect(info.width == 3_840)
        #expect(info.height == 2_160)
        #expect(info.videoCodec == "HEVC")
        #expect(info.dynamicRange == .dolbyVision)
        #expect(info.frameRate == 23.976)
        #expect(info.resolutionBadge == "4K")

        let audio = try #require(info.audioTracks.first)
        #expect(audio.codec == "Dolby Digital Plus")
        #expect(audio.channels == 8)
        #expect(audio.isAtmos)
        #expect(audio.language == "eng")

        let subtitle = try #require(info.subtitleTracks.first)
        #expect(subtitle.codec == "Timed Text")
        #expect(subtitle.language == "fra")

        // The QuickTime creation date (with its time zone) wins over mvhd's.
        #expect(info.creationDate == Date(timeIntervalSince1970: 1_710_497_554))
        #expect(info.location == "+37.7858-122.4064+010.000/")
    }

    @Test func eac3WithoutJointObjectCoding() {
        let payload = VideoFixtures.dec3(atmos: false).dropFirst(8)
        let result = MP4.eac3Channels(payload)
        #expect(result?.0 == 8)
        #expect(result?.1 == false)
    }

    @Test(arguments: [false, true])
    func matroska(clusterBeforeTracks: Bool) throws {
        let info = try #require(try VideoProbe.read(DataByteSource(VideoFixtures.mkv(clusterBeforeTracks: clusterBeforeTracks))))
        #expect(info.container == "Matroska")
        #expect(info.duration == 7_200)
        #expect(info.title == "A Movie")
        #expect(info.videoCodec == "HEVC")
        #expect(info.width == 3_840)
        #expect(info.height == 1_600)
        #expect(info.dynamicRange == .hdr10)
        #expect(info.resolutionBadge == "4K")
        #expect(info.frameRate == 23.976)
        #expect(info.audioTracks.count == 2)
        #expect(info.audioTracks.first?.codec == "Dolby TrueHD")
        #expect(info.audioTracks.first?.isAtmos == true)
        #expect(info.audioTracks.first?.channels == 8)
        #expect(info.audioTracks.last?.language == nil)
        #expect(info.audioTracks.last?.isDefault == false)
        #expect(info.subtitleTracks.first?.codec == "PGS")
        #expect(info.subtitleTracks.first?.isForced == true)
        #expect(info.subtitleTracks.first?.language == "spa")
        #expect(info.coverArt == Data(Fixtures.jpeg))
        #expect(info.hasAtmos)
        #expect(info.maximumAudioChannels == 8)
    }

    @Test func avi() throws {
        let info = try #require(try VideoProbe.read(DataByteSource(VideoFixtures.avi())))
        #expect(info.container == "AVI")
        #expect(info.width == 720)
        #expect(info.height == 480)
        #expect(info.videoCodec == "Xvid")
        #expect(info.frameRate == 29.97)
        #expect(abs((info.duration ?? 0) - 3_003) < 0.01)
        #expect(info.audioTracks.first?.codec == "Dolby Digital")
        #expect(info.audioTracks.first?.channels == 6)
        #expect(info.resolutionBadge == "SD")
    }

    @Test func unknownContainers() throws {
        #expect(try VideoProbe.read(DataByteSource(Fixtures.ascii("not a video at all"))) == nil)
    }

    @Test func cameraDates() {
        #expect(MediaDate.parse("2024-03-15T10:12:34Z") == Date(timeIntervalSince1970: 1_710_497_554))
        #expect(MediaDate.parse("2024-03-15T11:12:34+01:00") == Date(timeIntervalSince1970: 1_710_497_554))
        #expect(MediaDate.parse("2024-03-15T05:12:34.120-0500") == Date(timeIntervalSince1970: 1_710_497_554))
        #expect(MediaDate.parse("yesterday") == nil)
    }
}

@Suite("NFO files")
struct NFOTests {
    @Test func movie() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes" ?>
        <movie>
            <title>Heat</title>
            <originaltitle>Heat</originaltitle>
            <year>1995</year>
            <plot>A group of professional bank robbers start to feel the heat.</plot>
            <runtime>170</runtime>
            <mpaa>Rated R</mpaa>
            <genre>Action</genre>
            <genre>Crime / Drama</genre>
            <director>Michael Mann</director>
            <uniqueid type="imdb">tt0113277</uniqueid>
            <uniqueid type="tmdb" default="true">949</uniqueid>
            <actor><name>Al Pacino</name><role>Lt. Vincent Hanna</role><thumb>https://image.example/pacino.jpg</thumb></actor>
            <actor><name>Robert De Niro</name><role>Neil McCauley</role></actor>
            <ratings><rating name="themoviedb" max="10"><value>7.9</value></rating></ratings>
        </movie>
        """
        let info = try #require(NFOInfo.parse(Data(xml.utf8)))
        #expect(info.kind == .movie)
        #expect(info.title == "Heat")
        #expect(info.year == 1995)
        #expect(info.runtime == 170)
        #expect(info.contentRating == "R")
        #expect(info.genres == ["Action", "Crime", "Drama"])
        #expect(info.directors == ["Michael Mann"])
        #expect(info.tmdbID == 949)
        #expect(info.imdbID == "tt0113277")
        #expect(info.cast.count == 2)
        #expect(info.cast.first?.role == "Lt. Vincent Hanna")
        #expect(info.cast.first?.imageURL == "https://image.example/pacino.jpg")
        #expect(info.rating == 7.9)
    }

    @Test func episodeAndShow() throws {
        let episode = try #require(NFOInfo.parse(Data("""
        <episodedetails><title>Pilot</title><showtitle>Breaking Bad</showtitle><season>1</season><episode>1</episode><aired>2008-01-20</aired><plot>Walter White…</plot></episodedetails>
        """.utf8)))
        #expect(episode.kind == .episode)
        #expect(episode.season == 1)
        #expect(episode.episode == 1)
        #expect(episode.releaseDate == "2008-01-20")
        #expect(episode.year == 2008)
        #expect(episode.showTitle == "Breaking Bad")

        let show = try #require(NFOInfo.parse(Data("""
        <tvshow><title>Breaking Bad</title><premiered>2008-01-20</premiered><uniqueid type="tmdb">1396</uniqueid><id>81189</id></tvshow>
        """.utf8)))
        #expect(show.kind == .show)
        #expect(show.tmdbID == 1396)
        #expect(show.tvdbID == 81189)
    }

    @Test func linkOnly() throws {
        let imdb = try #require(NFOInfo.parse(Data("https://www.imdb.com/title/tt0113277/".utf8)))
        #expect(imdb.imdbID == "tt0113277")
        let tmdb = try #require(NFOInfo.parse(Data("https://www.themoviedb.org/movie/949-heat".utf8)))
        #expect(tmdb.tmdbID == 949)
        #expect(tmdb.kind == .movie)
        #expect(NFOInfo.parse(Data("just some release notes".utf8)) == nil)
    }
}
