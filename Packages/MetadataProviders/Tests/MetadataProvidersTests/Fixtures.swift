import Foundation

/// Builds small synthetic media files, byte by byte, for the reader tests.
enum Fixtures {
    // MARK: Integers

    /// Concatenates byte arrays (long `+` chains are slow to type-check).
    static func join(_ parts: [UInt8]...) -> [UInt8] {
        parts.flatMap { $0 }
    }

    static func be16(_ value: Int) -> [UInt8] { [UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)] }
    static func be24(_ value: Int) -> [UInt8] { [UInt8(value >> 16 & 0xFF), UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)] }
    static func be32(_ value: Int) -> [UInt8] { [UInt8(value >> 24 & 0xFF), UInt8(value >> 16 & 0xFF), UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)] }
    static func le16(_ value: Int) -> [UInt8] { [UInt8(value & 0xFF), UInt8(value >> 8 & 0xFF)] }
    static func le32(_ value: Int) -> [UInt8] { [UInt8(value & 0xFF), UInt8(value >> 8 & 0xFF), UInt8(value >> 16 & 0xFF), UInt8(value >> 24 & 0xFF)] }
    static func le64(_ value: Int64) -> [UInt8] { (0..<8).map { UInt8((value >> (8 * Int64($0))) & 0xFF) } }
    static func syncsafe(_ value: Int) -> [UInt8] {
        [UInt8(value >> 21 & 0x7F), UInt8(value >> 14 & 0x7F), UInt8(value >> 7 & 0x7F), UInt8(value & 0x7F)]
    }
    static func ascii(_ text: String) -> [UInt8] { Array(text.utf8) }
    static func latin1(_ text: String) -> [UInt8] { text.unicodeScalars.map { UInt8($0.value) } }
    static func utf16LEWithBOM(_ text: String) -> [UInt8] {
        [0xFF, 0xFE] + text.utf16.flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] }
    }

    /// A tiny but valid-looking JPEG (just the markers the MIME sniffer needs).
    static let jpeg: [UInt8] = [0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10] + ascii("JFIF") + [0x00, 0x01, 0x02, 0x03, 0xFF, 0xD9]
    static let png: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D]

    // MARK: ID3v2

    static func id3v23Frame(_ id: String, _ body: [UInt8]) -> [UInt8] {
        ascii(id) + be32(body.count) + [0, 0] + body
    }

    static func id3v24Frame(_ id: String, _ body: [UInt8]) -> [UInt8] {
        ascii(id) + syncsafe(body.count) + [0, 0] + body
    }

    static func id3v22Frame(_ id: String, _ body: [UInt8]) -> [UInt8] {
        ascii(id) + be24(body.count) + body
    }

    static func id3Tag(version: UInt8, frames: [[UInt8]], padding: Int = 16) -> [UInt8] {
        let body = frames.flatMap { $0 } + [UInt8](repeating: 0, count: padding)
        return ascii("ID3") + [version, 0, 0] + syncsafe(body.count) + body
    }

    static func latin1Text(_ text: String) -> [UInt8] { [0] + latin1(text) }
    static func utf16Text(_ text: String) -> [UInt8] { [1] + utf16LEWithBOM(text) }
    static func utf8Text(_ text: String) -> [UInt8] { [3] + ascii(text) }

    static func apic(_ image: [UInt8], type: UInt8 = 3) -> [UInt8] {
        [0] + ascii("image/jpeg") + [0, type] + ascii("Cover") + [0] + image
    }

    // MARK: MPEG audio

    /// One MPEG-1 Layer III frame header (128 kbps, 44.1 kHz, stereo) with a
    /// Xing header announcing `frames` frames, followed by more frames.
    static func mp3Stream(frames: Int, extraFrames: Int = 3) -> [UInt8] {
        let header: [UInt8] = [0xFF, 0xFB, 0x90, 0x00] // 128 kbps, 44100 Hz, no padding, stereo
        let frameLength = 144 * 128_000 / 44_100 // 417
        var first = header + [UInt8](repeating: 0, count: 32) + ascii("Xing") + be32(0x01) + be32(frames)
        first += [UInt8](repeating: 0, count: frameLength - first.count)
        var stream = first
        for _ in 0..<extraFrames {
            var frame = header
            frame += [UInt8](repeating: 0x55, count: frameLength - frame.count)
            stream += frame
        }
        return stream
    }

    /// CBR frames with no Xing header.
    static func cbrStream(frameCount: Int) -> [UInt8] {
        let header: [UInt8] = [0xFF, 0xFB, 0x90, 0x00]
        let frameLength = 144 * 128_000 / 44_100
        var stream: [UInt8] = []
        for _ in 0..<frameCount {
            stream += header + [UInt8](repeating: 0x11, count: frameLength - 4)
        }
        return stream
    }

    static func id3v1(title: String, artist: String, album: String, year: String, track: UInt8, genre: UInt8) -> [UInt8] {
        func field(_ text: String, _ length: Int) -> [UInt8] {
            Array((latin1(text) + [UInt8](repeating: 0, count: length)).prefix(length))
        }
        let trackBytes: [UInt8] = [0, track, genre]
        return join(ascii("TAG"), field(title, 30), field(artist, 30), field(album, 30), field(year, 4), field("", 28), trackBytes)
    }

    // MARK: FLAC and Vorbis comments

    static func vorbisComment(_ entries: [String]) -> [UInt8] {
        let vendor = ascii("Coreplay tests")
        var bytes = le32(vendor.count) + vendor + le32(entries.count)
        for entry in entries {
            let data = Array(entry.utf8)
            bytes += le32(data.count) + data
        }
        return bytes
    }

    static func flacPicture(_ image: [UInt8], type: Int = 3) -> [UInt8] {
        let mime = ascii("image/png")
        return be32(type) + be32(mime.count) + mime + be32(0) + be32(500) + be32(500) + be32(24) + be32(0) + be32(image.count) + image
    }

    static func streamInfo(sampleRate: Int, channels: Int, bitsPerSample: Int, totalSamples: Int64) -> [UInt8] {
        var bytes: [UInt8] = be16(4096) + be16(4096) + be24(0) + be24(0)
        // 20 bits rate, 3 bits channels-1, 5 bits bps-1, 36 bits total samples.
        let rate = sampleRate
        let ch = channels - 1
        let bps = bitsPerSample - 1
        let byte10 = UInt8(truncatingIfNeeded: rate >> 12)
        let byte11 = UInt8(truncatingIfNeeded: rate >> 4)
        let rateLow: Int = (rate & 0x0F) << 4
        let channelBits: Int = (ch & 0x07) << 1
        let depthHigh: Int = (bps >> 4) & 0x01
        let byte12 = UInt8(truncatingIfNeeded: rateLow | channelBits | depthHigh)
        let depthLow: Int = (bps & 0x0F) << 4
        let samplesHigh = Int(truncatingIfNeeded: (totalSamples >> 32) & 0x0F)
        let byte13 = UInt8(truncatingIfNeeded: depthLow | samplesHigh)
        bytes += [byte10, byte11, byte12, byte13]
        bytes += be32(Int(totalSamples & 0xFFFF_FFFF))
        bytes += [UInt8](repeating: 0, count: 16) // MD5
        return bytes
    }

    static func flacBlock(type: UInt8, isLast: Bool, _ body: [UInt8]) -> [UInt8] {
        [type | (isLast ? 0x80 : 0)] + be24(body.count) + body
    }

    // MARK: Ogg

    /// Wraps packets into Ogg pages (one packet per page, laced into 255-byte segments).
    static func oggPage(_ packet: [UInt8], granule: Int64, serial: Int = 0x1234, sequence: Int, headerType: UInt8 = 0) -> [UInt8] {
        var segments: [UInt8] = []
        var remaining = packet.count
        repeat {
            let segment = min(remaining, 255)
            segments.append(UInt8(segment))
            remaining -= segment
            if segment < 255 { break }
        } while true
        let flags: [UInt8] = [0, headerType]
        let count: [UInt8] = [UInt8(segments.count)]
        return join(ascii("OggS"), flags, le64(granule), le32(serial), le32(sequence), le32(0), count, segments, packet)
    }

    // MARK: MP4

    static func box(_ type: String, _ payload: [UInt8]) -> [UInt8] {
        be32(8 + payload.count) + latin1(type) + payload
    }

    static func fullBox(_ type: String, version: UInt8 = 0, _ payload: [UInt8]) -> [UInt8] {
        box(type, [version, 0, 0, 0] + payload)
    }

    static func dataBox(type: Int, _ value: [UInt8]) -> [UInt8] {
        box("data", be32(type) + be32(0) + value)
    }

    static func audioSampleEntry(_ type: String, channels: Int, sampleSize: Int, sampleRate: Int, children: [UInt8] = []) -> [UInt8] {
        let reserved = [UInt8](repeating: 0, count: 6)
        let reserved8 = [UInt8](repeating: 0, count: 8)
        let fields = join(reserved, be16(1), reserved8, be16(channels), be16(sampleSize), be16(0), be16(0), be32(sampleRate << 16))
        return box(type, fields + children)
    }

    // MARK: APEv2

    static func apeTag(_ items: [(String, [UInt8], binary: Bool)]) -> [UInt8] {
        var body: [UInt8] = []
        for (key, value, binary) in items {
            body += le32(value.count) + le32(binary ? 0x02 : 0) + ascii(key) + [0] + value
        }
        let footer = ascii("APETAGEX") + le32(2000) + le32(body.count + 32) + le32(items.count) + le32(0) + [UInt8](repeating: 0, count: 8)
        return body + footer
    }
}
