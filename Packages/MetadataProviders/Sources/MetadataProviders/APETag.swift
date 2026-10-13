import Foundation

/// APEv2 tags (Monkey's Audio, WavPack, Musepack, and some MP3s), found at
/// the end of the file, before an ID3v1 tag if there is one.
enum APETag {
    /// Looks for a tag whose footer ends at `end`. Returns the tags and the
    /// offset where the tag begins (so callers can look before it).
    static func parse(_ source: ByteSource, endingAt end: Int64) throws -> (tags: AudioTags, start: Int64)? {
        guard end >= 32 else { return nil }
        let footer = try source.bytes(at: end - 32, count: 32)
        guard footer.count == 32, Bytes.matches(footer, 0, "APETAGEX") else { return nil }
        let size = Int64(try Bytes.u32le(footer, 12)) // items + footer
        let count = Int(try Bytes.u32le(footer, 16))
        let flags = try Bytes.u32le(footer, 20)
        let hasHeader = flags & 0x8000_0000 != 0
        guard size >= 32, size <= end, size <= Int64(TagReader.maximumArtworkBytes) * 2 else { return nil }
        let itemsStart = end - size
        let items = try source.bytes(at: itemsStart, count: Int(size - 32))
        let tagStart = itemsStart - (hasHeader ? 32 : 0)

        var reader = ByteReader(items)
        var fields: [String: String] = [:]
        var artwork: EmbeddedArtwork?
        for _ in 0..<min(count, 1_000) {
            guard let valueSize = try? reader.u32le(), let itemFlags = try? reader.u32le() else { break }
            guard let terminator = items[reader.offset...].firstIndex(of: 0) else { break }
            let key = Bytes.ascii(items[reader.offset..<terminator]).lowercased()
            reader.offset = terminator + 1
            guard let value = try? reader.take(Int(valueSize)) else { break }
            let kind = (itemFlags >> 1) & 0x03
            if kind == 0 {
                if let text = Text.cleaned(Text.utf8(value)) {
                    fields[key] = text
                }
            } else if kind == 1, key == "cover art (front)" || (artwork == nil && key.hasPrefix("cover art")) {
                // Binary: a file name, NUL, then the image.
                if let separator = value.firstIndex(of: 0) {
                    let data = Data(value[(separator + 1)...])
                    if !data.isEmpty {
                        artwork = EmbeddedArtwork(data: data, mimeType: Text.imageMIMEType(data), pictureType: key == "cover art (front)" ? 3 : 0)
                    }
                }
            }
        }

        var tags = AudioTags()
        tags.title = fields["title"]
        tags.artist = fields["artist"]
        tags.album = fields["album"]
        tags.albumArtist = fields["album artist"] ?? fields["albumartist"]
        tags.composer = fields["composer"]
        tags.genre = ID3Genre.resolve(fields["genre"])
        tags.year = Text.year(fields["year"] ?? fields["date"])
        (tags.trackNumber, tags.trackCount) = Text.numberPair(fields["track"])
        (tags.discNumber, tags.discCount) = Text.numberPair(fields["disc"] ?? fields["discnumber"])
        tags.isCompilation = Text.bool(fields["compilation"])
        tags.lyrics = fields["lyrics"] ?? fields["unsyncedlyrics"]
        tags.comment = fields["comment"]
        tags.sortAlbum = fields["albumsort"]
        tags.sortArtist = fields["artistsort"]
        tags.sortTitle = fields["titlesort"]
        tags.sortAlbumArtist = fields["albumartistsort"]
        tags.musicBrainzRecordingID = fields["musicbrainz_trackid"]
        tags.musicBrainzAlbumID = fields["musicbrainz_albumid"]
        tags.musicBrainzArtistID = fields["musicbrainz_artistid"]
        tags.artwork = artwork
        return (tags, tagStart)
    }
}
