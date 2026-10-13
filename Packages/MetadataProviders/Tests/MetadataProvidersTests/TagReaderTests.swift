import Foundation
import Testing
@testable import MetadataProviders

@Suite("ID3 and MPEG audio")
struct ID3Tests {
    @Test func id3v23WithUTF16TextArtworkAndXingDuration() throws {
        let tag = Fixtures.id3Tag(version: 3, frames: [
            Fixtures.id3v23Frame("TIT2", Fixtures.utf16Text("Paranoid Android")),
            Fixtures.id3v23Frame("TPE1", Fixtures.latin1Text("Radiohead")),
            Fixtures.id3v23Frame("TALB", Fixtures.latin1Text("OK Computer")),
            Fixtures.id3v23Frame("TPE2", Fixtures.latin1Text("Radiohead")),
            Fixtures.id3v23Frame("TCON", Fixtures.latin1Text("(17)")),
            Fixtures.id3v23Frame("TYER", Fixtures.latin1Text("1997")),
            Fixtures.id3v23Frame("TRCK", Fixtures.latin1Text("2/12")),
            Fixtures.id3v23Frame("TPOS", Fixtures.latin1Text("1/1")),
            Fixtures.id3v23Frame("APIC", Fixtures.apic(Fixtures.jpeg)),
            Fixtures.id3v23Frame("USLT", [0] + Fixtures.ascii("eng") + [0] + Fixtures.ascii("Please could you stop the noise")),
        ])
        let file = tag + Fixtures.mp3Stream(frames: 1000)
        let tags = try TagReader.read(DataByteSource(file))
        #expect(tags.title == "Paranoid Android")
        #expect(tags.artist == "Radiohead")
        #expect(tags.album == "OK Computer")
        #expect(tags.albumArtist == "Radiohead")
        #expect(tags.genre == "Rock")
        #expect(tags.year == 1997)
        #expect(tags.trackNumber == 2)
        #expect(tags.trackCount == 12)
        #expect(tags.discNumber == 1)
        #expect(tags.lyrics == "Please could you stop the noise")
        #expect(tags.artwork?.data == Data(Fixtures.jpeg))
        #expect(tags.artwork?.mimeType == "image/jpeg")
        let duration = try #require(tags.duration)
        #expect(abs(duration - 1000.0 * 1152 / 44_100) < 0.01)
        #expect(tags.format?.codec == "MP3")
        #expect(tags.format?.sampleRate == 44_100)
        #expect(tags.format?.isLossless == false)
    }

    @Test func id3v24UTF8MultipleValuesAndRecordingDate() throws {
        let tag = Fixtures.id3Tag(version: 4, frames: [
            Fixtures.id3v24Frame("TIT2", Fixtures.utf8Text("Señorita")),
            Fixtures.id3v24Frame("TPE1", Fixtures.utf8Text("Beyoncé")),
            Fixtures.id3v24Frame("TCON", Fixtures.utf8Text("Pop") + [0] + Fixtures.ascii("R&B")),
            Fixtures.id3v24Frame("TDRC", Fixtures.utf8Text("2003-06-24")),
            Fixtures.id3v24Frame("TCMP", Fixtures.utf8Text("1")),
            Fixtures.id3v24Frame("TXXX", [3] + Fixtures.ascii("MusicBrainz Album Id") + [0] + Fixtures.ascii("abc-123")),
        ])
        let tags = try TagReader.read(DataByteSource(tag + Fixtures.mp3Stream(frames: 10)))
        #expect(tags.title == "Señorita")
        #expect(tags.artist == "Beyoncé")
        #expect(tags.genre == "Pop")
        #expect(tags.year == 2003)
        #expect(tags.isCompilation == true)
        #expect(tags.musicBrainzAlbumID == "abc-123")
    }

    @Test func id3v24WithNonSyncsafeFrameSizesFromOldEncoders() throws {
        // A 200-byte frame written with a plain 32-bit size: 0x000000C8 isn't
        // valid syncsafe (0xC8 has the high bit set).
        let longTitle = String(repeating: "x", count: 199)
        let frame = Fixtures.ascii("TIT2") + Fixtures.be32(200) + [0, 0] + Fixtures.latin1Text(longTitle)
        let next = Fixtures.id3v24Frame("TPE1", Fixtures.latin1Text("Artist"))
        let tags = try TagReader.read(DataByteSource(Fixtures.id3Tag(version: 4, frames: [frame, next])))
        #expect(tags.title == longTitle)
        #expect(tags.artist == "Artist")
    }

    @Test func id3v22ThreeLetterFrames() throws {
        let picture: [UInt8] = [0] + Fixtures.ascii("PNG") + [3, 0] + Fixtures.png
        let tag = Fixtures.id3Tag(version: 2, frames: [
            Fixtures.id3v22Frame("TT2", Fixtures.latin1Text("Old Song")),
            Fixtures.id3v22Frame("TP1", Fixtures.latin1Text("Old Artist")),
            Fixtures.id3v22Frame("TAL", Fixtures.latin1Text("Old Album")),
            Fixtures.id3v22Frame("TRK", Fixtures.latin1Text("7")),
            Fixtures.id3v22Frame("PIC", picture),
        ])
        let tags = try TagReader.read(DataByteSource(tag))
        #expect(tags.title == "Old Song")
        #expect(tags.artist == "Old Artist")
        #expect(tags.album == "Old Album")
        #expect(tags.trackNumber == 7)
        #expect(tags.artwork?.mimeType == "image/png")
    }

    @Test func frontCoverWinsOverOtherPictures() throws {
        let back = Fixtures.apic(Fixtures.png, type: 4)
        let front = Fixtures.apic(Fixtures.jpeg, type: 3)
        let tag = Fixtures.id3Tag(version: 3, frames: [
            Fixtures.id3v23Frame("APIC", back),
            Fixtures.id3v23Frame("APIC", front),
        ])
        let tags = try TagReader.read(DataByteSource(tag))
        #expect(tags.artwork?.data == Data(Fixtures.jpeg))
    }

    @Test func id3v1FillsWhatID3v2Lacks() throws {
        let tag = Fixtures.id3Tag(version: 3, frames: [
            Fixtures.id3v23Frame("TIT2", Fixtures.latin1Text("From ID3v2")),
        ])
        let v1 = Fixtures.id3v1(title: "From ID3v1", artist: "V1 Artist", album: "V1 Album", year: "1985", track: 4, genre: 13)
        let tags = try TagReader.read(DataByteSource(tag + Fixtures.cbrStream(frameCount: 20) + v1))
        #expect(tags.title == "From ID3v2")
        #expect(tags.artist == "V1 Artist")
        #expect(tags.album == "V1 Album")
        #expect(tags.year == 1985)
        #expect(tags.trackNumber == 4)
        #expect(tags.genre == "Pop")
    }

    @Test func cbrDurationFromBitRateWithoutXingHeader() throws {
        let tags = try TagReader.read(DataByteSource(Fixtures.cbrStream(frameCount: 100)))
        let duration = try #require(tags.duration)
        #expect(abs(duration - 100.0 * 1152 / 44_100) < 0.05)
        #expect(tags.format?.bitRate == 128_000)
    }

    @Test func genreReferences() {
        #expect(ID3Genre.resolve("(17)") == "Rock")
        #expect(ID3Genre.resolve("17") == "Rock")
        #expect(ID3Genre.resolve("(17)Hard Rock") == "Hard Rock")
        #expect(ID3Genre.resolve("(RX)") == "Remix")
        #expect(ID3Genre.resolve("Shoegaze") == "Shoegaze")
        #expect(ID3Genre.resolve("") == nil)
        #expect(ID3Genre.name(for: 191) == "Psybient")
        #expect(ID3Genre.name(for: 255) == nil)
    }

    @Test func unsynchronisationIsRemoved() {
        #expect(ID3v2.removeUnsynchronisation([0xFF, 0x00, 0xE0, 0x41, 0xFF, 0x00]) == [0xFF, 0xE0, 0x41, 0xFF])
    }

    @Test func truncatedTagsDoNotCrash() throws {
        let tag = Fixtures.id3Tag(version: 3, frames: [Fixtures.id3v23Frame("TIT2", Fixtures.latin1Text("Cut"))])
        for length in stride(from: 0, through: tag.count, by: 3) {
            _ = try TagReader.read(DataByteSource(Array(tag.prefix(length))))
        }
    }
}

@Suite("FLAC, Ogg, MP4, RIFF and APE")
struct ContainerTests {
    @Test func flacStreamInfoCommentsAndPicture() throws {
        let comment = Fixtures.vorbisComment([
            "TITLE=Teardrop", "ARTIST=Massive Attack", "ALBUM=Mezzanine", "ALBUMARTIST=Massive Attack",
            "DATE=1998-04-20", "TRACKNUMBER=3", "TRACKTOTAL=11", "DISCNUMBER=1/1", "GENRE=Trip-Hop",
            "MUSICBRAINZ_TRACKID=rec-1",
        ])
        let file = Fixtures.ascii("fLaC")
            + Fixtures.flacBlock(type: 0, isLast: false, Fixtures.streamInfo(sampleRate: 96_000, channels: 2, bitsPerSample: 24, totalSamples: 96_000 * 330))
            + Fixtures.flacBlock(type: 4, isLast: false, comment)
            + Fixtures.flacBlock(type: 6, isLast: true, Fixtures.flacPicture(Fixtures.png))
            + [UInt8](repeating: 0, count: 64)
        let tags = try TagReader.read(DataByteSource(file))
        #expect(tags.title == "Teardrop")
        #expect(tags.artist == "Massive Attack")
        #expect(tags.album == "Mezzanine")
        #expect(tags.year == 1998)
        #expect(tags.trackNumber == 3)
        #expect(tags.trackCount == 11)
        #expect(tags.discNumber == 1)
        #expect(tags.discCount == 1)
        #expect(tags.genre == "Trip-Hop")
        #expect(tags.musicBrainzRecordingID == "rec-1")
        #expect(tags.artwork?.data == Data(Fixtures.png))
        #expect(tags.duration == 330)
        #expect(tags.format == AudioFormatInfo(codec: "FLAC", sampleRate: 96_000, channels: 2, bitsPerSample: 24, isLossless: true))
        #expect(tags.format?.isHighResolution == true)
    }

    @Test func vorbisCommentMultipleArtistsAndBase64Picture() throws {
        let picture = Data(Fixtures.flacPicture(Fixtures.jpeg)).base64EncodedString()
        let tags = VorbisComment.parse(Fixtures.vorbisComment([
            "artist=Daft Punk", "ARTIST=Pharrell Williams", "Title=Get Lucky",
            "METADATA_BLOCK_PICTURE=\(picture)", "COMPILATION=0",
        ]))
        #expect(tags.artist == "Daft Punk, Pharrell Williams")
        #expect(tags.title == "Get Lucky")
        #expect(tags.isCompilation == false)
        #expect(tags.artwork?.data == Data(Fixtures.jpeg))
    }

    @Test func oggVorbisCommentsAndDurationFromLastGranule() throws {
        var identification: [UInt8] = [0x01] + Fixtures.ascii("vorbis") + Fixtures.le32(0) + [2] + Fixtures.le32(44_100)
        identification += Fixtures.le32(0) + Fixtures.le32(160_000) + Fixtures.le32(0) + [0xB8, 0x01]
        let comment = [0x03] + Fixtures.ascii("vorbis") + Fixtures.vorbisComment(["TITLE=Ogg Song", "ARTIST=Ogg Artist"]) + [0x01]
        let file = Fixtures.oggPage(identification, granule: 0, sequence: 0, headerType: 0x02)
            + Fixtures.oggPage(comment, granule: 0, sequence: 1)
            + Fixtures.oggPage([UInt8](repeating: 0x42, count: 100), granule: 44_100 * 200, sequence: 2, headerType: 0x04)
        let tags = try TagReader.read(DataByteSource(file))
        #expect(tags.title == "Ogg Song")
        #expect(tags.artist == "Ogg Artist")
        #expect(tags.duration == 200)
        #expect(tags.format?.codec == "Vorbis")
        #expect(tags.format?.bitRate == 160_000)
    }

    @Test func opusUsesPreSkipAnd48kGranules() throws {
        let head = Fixtures.join(Fixtures.ascii("OpusHead"), [1, 2], Fixtures.le16(312), Fixtures.le32(44_100), Fixtures.le16(0), [0])
        let tagsPacket = Fixtures.ascii("OpusTags") + Fixtures.vorbisComment(["TITLE=Opus Song"])
        let file = Fixtures.oggPage(head, granule: 0, sequence: 0, headerType: 0x02)
            + Fixtures.oggPage(tagsPacket, granule: 0, sequence: 1)
            + Fixtures.oggPage([1, 2, 3], granule: 48_000 * 60 + 312, sequence: 2, headerType: 0x04)
        let tags = try TagReader.read(DataByteSource(file))
        #expect(tags.title == "Opus Song")
        #expect(tags.duration == 60)
        #expect(tags.format?.codec == "Opus")
    }

    @Test func oggCommentPacketSpanningSeveralSegments() throws {
        let head = Fixtures.join(Fixtures.ascii("OpusHead"), [1, 2], Fixtures.le16(0), Fixtures.le32(48_000), Fixtures.le16(0), [0])
        let longLyrics = String(repeating: "la ", count: 400)
        let tagsPacket = Fixtures.ascii("OpusTags") + Fixtures.vorbisComment(["LYRICS=\(longLyrics)", "TITLE=Long"])
        let file = Fixtures.oggPage(head, granule: 0, sequence: 0, headerType: 0x02) + Fixtures.oggPage(tagsPacket, granule: 0, sequence: 1)
        let tags = try TagReader.read(DataByteSource(file))
        #expect(tags.title == "Long")
        #expect(tags.lyrics == longLyrics.trimmingCharacters(in: .whitespaces))
    }

    @Test func mp4ItemListDurationAndALACFormat() throws {
        let alacConfig = Fixtures.fullBox("alac", Fixtures.be32(4096) + [0, 24, 40, 10, 14, 2] + Fixtures.be16(255) + Fixtures.be32(0) + Fixtures.be32(0) + Fixtures.be32(192_000))
        let sampleEntry = Fixtures.audioSampleEntry("alac", channels: 2, sampleSize: 24, sampleRate: 0, children: alacConfig)
        let stsd = Fixtures.fullBox("stsd", Fixtures.be32(1) + sampleEntry)
        let trak = Fixtures.box("trak", Fixtures.box("mdia",
            Fixtures.fullBox("hdlr", Fixtures.be32(0) + Fixtures.ascii("soun") + [UInt8](repeating: 0, count: 13))
            + Fixtures.box("minf", Fixtures.box("stbl", stsd))))
        let mvhd = Fixtures.fullBox("mvhd", Fixtures.be32(0) + Fixtures.be32(0) + Fixtures.be32(1000) + Fixtures.be32(245_500) + [UInt8](repeating: 0, count: 80))
        let ilst = Fixtures.box("ilst",
            Fixtures.box("\u{A9}nam", Fixtures.dataBox(type: 1, Array("Cold Little Heart".utf8)))
            + Fixtures.box("\u{A9}ART", Fixtures.dataBox(type: 1, Array("Michael Kiwanuka".utf8)))
            + Fixtures.box("\u{A9}alb", Fixtures.dataBox(type: 1, Array("Love & Hate".utf8)))
            + Fixtures.box("aART", Fixtures.dataBox(type: 1, Array("Michael Kiwanuka".utf8)))
            + Fixtures.box("trkn", Fixtures.dataBox(type: 0, [0, 0, 0, 1, 0, 10, 0, 0]))
            + Fixtures.box("disk", Fixtures.dataBox(type: 0, [0, 0, 0, 1, 0, 1]))
            + Fixtures.box("gnre", Fixtures.dataBox(type: 0, [0, 43])) // Soul (42) + 1
            + Fixtures.box("cpil", Fixtures.dataBox(type: 21, [1]))
            + Fixtures.box("\u{A9}day", Fixtures.dataBox(type: 1, Array("2016-07-15T07:00:00Z".utf8)))
            + Fixtures.box("covr", Fixtures.dataBox(type: 13, Fixtures.jpeg))
            + Fixtures.box("----", Fixtures.fullBox("mean", Array("com.apple.iTunes".utf8)) + Fixtures.fullBox("name", Array("MusicBrainz Album Id".utf8)) + Fixtures.dataBox(type: 1, Array("rel-9".utf8))))
        let meta = Fixtures.fullBox("meta", Fixtures.fullBox("hdlr", Fixtures.be32(0) + Fixtures.ascii("mdir") + [UInt8](repeating: 0, count: 13)) + ilst)
        let moov = Fixtures.box("moov", mvhd + trak + Fixtures.box("udta", meta))
        // moov after a large-ish mdat, as many encoders write it.
        let file = Fixtures.box("ftyp", Fixtures.ascii("M4A ") + Fixtures.be32(0)) + Fixtures.box("mdat", [UInt8](repeating: 0, count: 4096)) + moov
        let tags = try TagReader.read(DataByteSource(file))
        #expect(tags.title == "Cold Little Heart")
        #expect(tags.artist == "Michael Kiwanuka")
        #expect(tags.album == "Love & Hate")
        #expect(tags.albumArtist == "Michael Kiwanuka")
        #expect(tags.trackNumber == 1)
        #expect(tags.trackCount == 10)
        #expect(tags.discNumber == 1)
        #expect(tags.genre == "Soul")
        #expect(tags.isCompilation == true)
        #expect(tags.year == 2016)
        #expect(tags.artwork?.data == Data(Fixtures.jpeg))
        #expect(tags.musicBrainzAlbumID == "rel-9")
        #expect(tags.duration == 245.5)
        #expect(tags.format?.codec == "ALAC")
        #expect(tags.format?.sampleRate == 192_000)
        #expect(tags.format?.bitsPerSample == 24)
        #expect(tags.format?.isLossless == true)
    }

    @Test func wavFormatInfoListAndDuration() throws {
        let fmt = Fixtures.le16(1) + Fixtures.le16(2) + Fixtures.le32(48_000) + Fixtures.le32(48_000 * 4) + Fixtures.le16(4) + Fixtures.le16(16)
        func sub(_ id: String, _ text: String) -> [UInt8] {
            let value = Array(text.utf8) + [0]
            return Fixtures.ascii(id) + Fixtures.le32(value.count) + value + (value.count % 2 == 1 ? [0] : [])
        }
        let list = Fixtures.ascii("INFO") + sub("INAM", "Field Recording") + sub("IART", "Someone") + sub("ICRD", "2020")
        let dataSize = 48_000 * 4 * 3
        var body = Fixtures.ascii("WAVE")
        body += Fixtures.ascii("fmt ") + Fixtures.le32(fmt.count) + fmt
        body += Fixtures.ascii("LIST") + Fixtures.le32(list.count) + list
        body += Fixtures.ascii("data") + Fixtures.le32(dataSize) + [UInt8](repeating: 0, count: 64)
        let file = Fixtures.ascii("RIFF") + Fixtures.le32(body.count) + body
        let tags = try TagReader.read(DataByteSource(file))
        #expect(tags.title == "Field Recording")
        #expect(tags.artist == "Someone")
        #expect(tags.year == 2020)
        #expect(tags.duration == 3)
        #expect(tags.format?.codec == "PCM")
        #expect(tags.format?.bitsPerSample == 16)
        #expect(tags.format?.isLossless == true)
    }

    @Test func aiffCommonChunkAndEmbeddedID3() throws {
        // 44100 as an 80-bit extended float: exponent 0x400E, mantissa 0xAC44 << 48.
        let rate: [UInt8] = [0x40, 0x0E, 0xAC, 0x44, 0, 0, 0, 0, 0, 0]
        let comm = Fixtures.be16(2) + Fixtures.be32(44_100 * 10) + Fixtures.be16(16) + rate
        let id3 = Fixtures.id3Tag(version: 3, frames: [Fixtures.id3v23Frame("TIT2", Fixtures.latin1Text("AIFF Song"))], padding: 0)
        var body = Fixtures.ascii("AIFF")
        body += Fixtures.ascii("COMM") + Fixtures.be32(comm.count) + comm
        body += Fixtures.ascii("ID3 ") + Fixtures.be32(id3.count) + id3 + (id3.count % 2 == 1 ? [0] : [])
        let file = Fixtures.ascii("FORM") + Fixtures.be32(body.count) + body
        let tags = try TagReader.read(DataByteSource(file))
        #expect(tags.title == "AIFF Song")
        #expect(tags.duration == 10)
        #expect(tags.format?.sampleRate == 44_100)
        #expect(RIFF.extendedFloat(rate) == 44_100)
    }

    @Test func apeTagWithCoverAndID3v1After() throws {
        let ape = Fixtures.apeTag([
            ("Title", Array("APE Title".utf8), binary: false),
            ("Artist", Array("APE Artist".utf8), binary: false),
            ("Track", Array("5/9".utf8), binary: false),
            ("Cover Art (Front)", Array("cover.jpg".utf8) + [0] + Fixtures.jpeg, binary: true),
        ])
        let v1 = Fixtures.id3v1(title: "V1", artist: "V1", album: "V1 Album", year: "1999", track: 1, genre: 0)
        let file = Fixtures.ascii("MAC ") + [UInt8](repeating: 0, count: 200) + ape + v1
        let tags = try TagReader.read(DataByteSource(file))
        #expect(tags.title == "APE Title")
        #expect(tags.artist == "APE Artist")
        #expect(tags.trackNumber == 5)
        #expect(tags.trackCount == 9)
        #expect(tags.album == "V1 Album")
        #expect(tags.artwork?.data == Data(Fixtures.jpeg))
        #expect(tags.format?.codec == "Monkey\u{2019}s Audio")
    }

    @Test func unknownFormatsReturnNothingRatherThanThrowing() throws {
        let tags = try TagReader.read(DataByteSource([UInt8](repeating: 0x30, count: 1000)))
        #expect(tags.hasDescriptiveTags == false)
        #expect(tags.duration == nil)
        let empty = try TagReader.read(DataByteSource([]))
        #expect(empty == AudioTags())
    }

    @Test func readsRealFilesThroughFileByteSource() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("coreplay-tag-test-\(UUID().uuidString).mp3")
        let tag = Fixtures.id3Tag(version: 3, frames: [Fixtures.id3v23Frame("TIT2", Fixtures.latin1Text("On Disk"))])
        try Data(tag + Fixtures.mp3Stream(frames: 50)).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let tags = try TagReader.read(url: url)
        #expect(tags.title == "On Disk")
        #expect(tags.duration != nil)
    }
}
