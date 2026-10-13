import Foundation

/// Reads embedded tags, artwork, duration and format from an audio file.
///
/// The container is recognised from its first bytes, not its extension:
/// ID3v2 + MPEG audio, FLAC, Ogg (Vorbis, Opus, FLAC), MP4/M4A, WAV and AIFF.
/// APEv2 and ID3v1 tags at the end of the file fill whatever the format's own
/// tags left empty. Unknown formats (WMA, for example) return what the trailing
/// tags provide, which may be nothing; the library then uses folder and file names.
///
/// Pure Swift and Foundation only, so it runs anywhere, including the tests on Linux.
public enum TagReader {
    /// Embedded pictures larger than this are ignored (and tags with them are
    /// read only up to roughly this size).
    public static let maximumArtworkBytes = 16 * 1024 * 1024

    public static func read(url: URL) throws -> AudioTags {
        try read(FileByteSource(url: url))
    }

    public static func read(_ source: ByteSource) throws -> AudioTags {
        var tags = AudioTags()
        var audioStart: Int64 = 0
        var audioEnd = source.size

        // Leading ID3v2 (MP3, AAC, sometimes FLAC).
        let head = try source.bytes(at: 0, count: 10)
        if let size = ID3v2.tagSize(header: head) {
            let readable = min(size, maximumArtworkBytes * 2)
            if let id3 = ID3v2.parse(try source.bytes(at: 0, count: readable)) {
                tags = id3
            }
            audioStart = Int64(size)
        }

        // Trailing ID3v1 and APEv2.
        var trailing = AudioTags()
        if source.size >= 128 {
            let tail = try source.bytes(at: source.size - 128, count: 128)
            if Bytes.matches(tail, 0, "TAG") {
                audioEnd -= 128
                if let v1 = ID3v1.parse(tail) {
                    trailing = v1
                }
            }
        }
        var ape: AudioTags?
        if let (apeTags, apeStart) = try APETag.parse(source, endingAt: audioEnd) {
            ape = apeTags
            audioEnd = apeStart
        }

        // The format's own tags and stream information.
        let magic = try source.bytes(at: audioStart, count: 12)
        var native = AudioTags()
        if Bytes.matches(magic, 0, "fLaC") {
            native = try FLAC.parse(source, at: audioStart)
        } else if Bytes.matches(magic, 0, "OggS") {
            native = try Ogg.parse(source)
        } else if Bytes.matches(magic, 4, "ftyp") {
            native = try MP4.parse(source)
        } else if Bytes.matches(magic, 0, "RIFF"), Bytes.matches(magic, 8, "WAVE") {
            native = try RIFF.parseWAV(source)
        } else if Bytes.matches(magic, 0, "FORM"), Bytes.matches(magic, 8, "AIFF") || Bytes.matches(magic, 8, "AIFC") {
            native = try RIFF.parseAIFF(source, isCompressed: Bytes.matches(magic, 8, "AIFC"))
        } else if Bytes.matches(magic, 0, "MAC ") {
            native.format = AudioFormatInfo(codec: "Monkey\u{2019}s Audio", isLossless: true)
        } else if Bytes.matches(magic, 0, "wvpk") {
            native.format = AudioFormatInfo(codec: "WavPack", isLossless: true)
        } else if Bytes.matches(magic, 0, "MPCK") || Bytes.matches(magic, 0, "MP+") {
            native.format = AudioFormatInfo(codec: "Musepack", isLossless: false)
        } else if magic.count >= 2, magic[0] == 0xFF, magic[1] & 0xF6 == 0xF0 {
            let (duration, format) = try ADTS.analyse(source, audioStart: audioStart, audioEnd: audioEnd)
            native.duration = duration
            native.format = format
        } else if magic.first == 0xFF {
            let (duration, format) = try MPEGAudio.analyse(source, audioStart: audioStart, audioEnd: audioEnd)
            // A stream header beats ID3's TLEN, which taggers often get wrong.
            native.duration = duration
            native.format = format
        }

        // Priority: the format's own tags, the leading ID3v2, APEv2, ID3v1.
        // Streams' durations win over tags' (they come from `native`).
        var result = native
        result.fillMissing(from: tags)
        if let ape {
            result.fillMissing(from: ape)
        }
        result.fillMissing(from: trailing)
        if let artwork = result.artwork, artwork.data.count > maximumArtworkBytes {
            result.artwork = nil
        }
        return result
    }
}
