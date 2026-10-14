import Foundation

/// Vorbis comments: the tag format of FLAC, Ogg Vorbis, Opus and Ogg FLAC.
enum VorbisComment {
    /// Parses a comment block (vendor string, then `KEY=value` entries).
    static func parse(_ bytes: [UInt8]) -> AudioTags {
        var reader = ByteReader(bytes)
        var fields: [String: [String]] = [:]
        var pictures: [EmbeddedArtwork] = []
        do {
            let vendorLength = Int(try reader.u32le())
            try reader.skip(vendorLength)
            let count = Int(try reader.u32le())
            for _ in 0..<min(count, 10_000) {
                let length = Int(try reader.u32le())
                let entry = try reader.take(length)
                guard let separator = entry.firstIndex(of: UInt8(ascii: "=")) else { continue }
                let key = Bytes.ascii(entry[entry.startIndex..<separator]).uppercased()
                let valueBytes = entry[(separator + 1)...]
                if key == "METADATA_BLOCK_PICTURE" {
                    if let decoded = Data(base64Encoded: Text.utf8(valueBytes), options: .ignoreUnknownCharacters),
                       let picture = FLACPicture.parse([UInt8](decoded)) {
                        pictures.append(picture)
                    }
                    continue
                }
                if key == "COVERART" {
                    if let decoded = Data(base64Encoded: Text.utf8(valueBytes), options: .ignoreUnknownCharacters), !decoded.isEmpty {
                        pictures.append(EmbeddedArtwork(data: decoded, mimeType: Text.imageMIMEType(decoded), pictureType: 3))
                    }
                    continue
                }
                if let value = Text.cleaned(Text.utf8(valueBytes)) {
                    fields[key, default: []].append(value)
                }
            }
        } catch {
            // A truncated block still yields the entries read so far.
        }

        func first(_ keys: String...) -> String? {
            for key in keys {
                if let value = fields[key]?.first { return value }
            }
            return nil
        }
        func joined(_ key: String) -> String? {
            guard let values = fields[key], !values.isEmpty else { return nil }
            return values.joined(separator: ", ")
        }

        var tags = AudioTags()
        tags.title = first("TITLE")
        tags.artist = joined("ARTIST")
        tags.album = first("ALBUM")
        tags.albumArtist = first("ALBUMARTIST", "ALBUM ARTIST", "ALBUM_ARTIST")
        tags.composer = joined("COMPOSER")
        tags.genre = first("GENRE")
        tags.year = Text.year(first("DATE", "YEAR", "ORIGINALDATE", "ORIGINALYEAR"))
        let (track, trackFromPair) = Text.numberPair(first("TRACKNUMBER"))
        tags.trackNumber = track
        tags.trackCount = trackFromPair ?? Text.numberPair(first("TRACKTOTAL", "TOTALTRACKS")).0
        let (disc, discFromPair) = Text.numberPair(first("DISCNUMBER"))
        tags.discNumber = disc
        tags.discCount = discFromPair ?? Text.numberPair(first("DISCTOTAL", "TOTALDISCS")).0
        tags.isCompilation = Text.bool(first("COMPILATION"))
        tags.lyrics = first("LYRICS", "UNSYNCEDLYRICS")
        tags.comment = first("COMMENT", "DESCRIPTION")
        tags.sortTitle = first("TITLESORT")
        tags.sortArtist = first("ARTISTSORT")
        tags.sortAlbum = first("ALBUMSORT")
        tags.sortAlbumArtist = first("ALBUMARTISTSORT")
        tags.musicBrainzRecordingID = first("MUSICBRAINZ_TRACKID")
        tags.musicBrainzAlbumID = first("MUSICBRAINZ_ALBUMID")
        tags.musicBrainzArtistID = first("MUSICBRAINZ_ARTISTID")
        var lowercased: [String: String] = [:]
        for (key, values) in fields where key.hasPrefix("REPLAYGAIN_") {
            lowercased[key.lowercased()] = values.first
        }
        tags.replayGain = ReplayGainTags.from(lowercasedFields: lowercased)
            ?? ReplayGainTags.fromR128(track: first("R128_TRACK_GAIN"), album: first("R128_ALBUM_GAIN"))
        tags.artwork = EmbeddedArtwork.best(of: pictures)
        return tags
    }
}

/// The FLAC PICTURE block, also used base64-encoded in Ogg comments.
enum FLACPicture {
    static func parse(_ bytes: [UInt8]) -> EmbeddedArtwork? {
        var reader = ByteReader(bytes)
        do {
            let type = Int(try reader.u32be())
            let mimeLength = Int(try reader.u32be())
            let mime = Text.latin1(try reader.take(mimeLength))
            let descriptionLength = Int(try reader.u32be())
            try reader.skip(descriptionLength)
            try reader.skip(16) // width, height, colour depth, palette size
            let dataLength = Int(try reader.u32be())
            let data = Data(try reader.take(dataLength))
            guard !data.isEmpty else { return nil }
            return EmbeddedArtwork(data: data, mimeType: Text.imageMIMEType(data) ?? Text.cleaned(mime), pictureType: type)
        } catch {
            return nil
        }
    }
}

/// Native FLAC files: "fLaC" followed by metadata blocks.
enum FLAC {
    /// Parses the metadata blocks of a FLAC stream that starts at `offset`.
    static func parse(_ source: ByteSource, at offset: Int64) throws -> AudioTags {
        var tags = AudioTags()
        var pictures: [EmbeddedArtwork] = []
        var position = offset + 4
        var isLast = false
        var blocks = 0
        while !isLast, blocks < 128 {
            let header = try source.bytes(at: position, count: 4)
            guard header.count == 4 else { break }
            isLast = header[0] & 0x80 != 0
            let type = header[0] & 0x7F
            let length = Int(try Bytes.u24be(header, 1))
            position += 4
            switch type {
            case 0: // STREAMINFO
                let info = try source.bytes(at: position, count: length)
                applyStreamInfo(info, to: &tags)
            case 4: // VORBIS_COMMENT
                let comment = VorbisComment.parse(try source.bytes(at: position, count: length))
                let artwork = comment.artwork
                tags.fillMissing(from: comment)
                if let artwork { pictures.append(artwork) }
            case 6: // PICTURE
                if length <= TagReader.maximumArtworkBytes,
                   let picture = FLACPicture.parse(try source.bytes(at: position, count: length)) {
                    pictures.append(picture)
                }
            case 127:
                isLast = true // invalid block type
            default:
                break
            }
            position += Int64(length)
            blocks += 1
        }
        tags.artwork = EmbeddedArtwork.best(of: pictures)
        return tags
    }

    /// STREAMINFO: sample rate, channels, bit depth and total samples → duration.
    static func applyStreamInfo(_ info: [UInt8], to tags: inout AudioTags) {
        guard info.count >= 18 else { return }
        let sampleRate = Int(info[10]) << 12 | Int(info[11]) << 4 | Int(info[12]) >> 4
        let channels = Int((info[12] >> 1) & 0x07) + 1
        let bitsPerSample = Int((info[12] & 0x01) << 4 | info[13] >> 4) + 1
        let totalSamples = Int64(info[13] & 0x0F) << 32 | Int64(info[14]) << 24 | Int64(info[15]) << 16 | Int64(info[16]) << 8 | Int64(info[17])
        if sampleRate > 0, totalSamples > 0 {
            tags.duration = Double(totalSamples) / Double(sampleRate)
        }
        tags.format = AudioFormatInfo(
            codec: "FLAC",
            sampleRate: sampleRate > 0 ? sampleRate : nil,
            channels: channels,
            bitsPerSample: bitsPerSample,
            isLossless: true
        )
    }
}
