import Foundation

/// Ogg Vorbis, Opus and Ogg FLAC: tags live in the second packet of the stream.
enum Ogg {
    struct Page {
        var offset: Int64
        var headerType: UInt8
        var granulePosition: Int64
        var serial: UInt32
        var segmentSizes: [Int]
        var headerLength: Int

        var bodyLength: Int { segmentSizes.reduce(0, +) }
        var totalLength: Int { headerLength + bodyLength }
    }

    static func readPage(_ source: ByteSource, at offset: Int64) throws -> Page? {
        let header = try source.bytes(at: offset, count: 27)
        guard header.count == 27, Bytes.matches(header, 0, "OggS") else { return nil }
        let segmentCount = Int(header[26])
        let table = try source.bytes(at: offset + 27, count: segmentCount)
        guard table.count == segmentCount else { return nil }
        return Page(
            offset: offset,
            headerType: header[5],
            granulePosition: Int64(bitPattern: try Bytes.u64le(header, 6)),
            serial: try Bytes.u32le(header, 14),
            segmentSizes: table.map(Int.init),
            headerLength: 27 + segmentCount
        )
    }

    /// Reassembles the first `count` packets of the first logical stream.
    static func packets(_ source: ByteSource, count: Int, byteLimit: Int) throws -> (packets: [[UInt8]], serial: UInt32?) {
        var packets: [[UInt8]] = []
        var current: [UInt8] = []
        var offset: Int64 = 0
        var serial: UInt32?
        var total = 0
        while packets.count < count, let page = try readPage(source, at: offset) {
            if serial == nil { serial = page.serial }
            if page.serial == serial {
                let body = try source.bytes(at: page.offset + Int64(page.headerLength), count: page.bodyLength)
                var cursor = 0
                for size in page.segmentSizes {
                    guard cursor + size <= body.count else { break }
                    current.append(contentsOf: body[cursor..<(cursor + size)])
                    cursor += size
                    total += size
                    if size < 255 {
                        packets.append(current)
                        current = []
                        if packets.count == count { break }
                    }
                }
                if total > byteLimit { break }
            }
            offset += Int64(page.totalLength)
        }
        return (packets, serial)
    }

    /// The granule position of the stream's last page, found by scanning the
    /// end of the file backwards for "OggS".
    static func lastGranulePosition(_ source: ByteSource, serial: UInt32?) throws -> Int64? {
        let window = Int(min(source.size, 128 * 1024))
        let start = source.size - Int64(window)
        let tail = try source.bytes(at: start, count: window)
        var index = tail.count - 27
        while index >= 0 {
            if tail[index] == 0x4F, Bytes.matches(tail, index, "OggS"),
               let granule = try? Bytes.u64le(tail, index + 6),
               let pageSerial = try? Bytes.u32le(tail, index + 14),
               serial == nil || pageSerial == serial {
                let value = Int64(bitPattern: granule)
                if value > 0 { return value }
            }
            index -= 1
        }
        return nil
    }

    static func parse(_ source: ByteSource) throws -> AudioTags {
        let (packets, serial) = try packets(source, count: 2, byteLimit: TagReader.maximumArtworkBytes + 1_048_576)
        guard let identification = packets.first else { return AudioTags() }
        var tags = AudioTags()
        var sampleRate = 0
        var preSkip = 0
        let commentPacket = packets.count > 1 ? packets[1] : []

        if Bytes.matches(identification, 0, "\u{01}vorbis"), identification.count >= 28 {
            let channels = Int(identification[11])
            sampleRate = Int((try? Bytes.u32le(identification, 12)) ?? 0)
            let nominalBitRate = Int(Int32(bitPattern: (try? Bytes.u32le(identification, 20)) ?? 0))
            tags.format = AudioFormatInfo(codec: "Vorbis", sampleRate: sampleRate, channels: channels, bitRate: nominalBitRate > 0 ? nominalBitRate : nil, isLossless: false)
            if Bytes.matches(commentPacket, 0, "\u{03}vorbis") {
                tags.fillMissing(from: VorbisComment.parse(Array(commentPacket.dropFirst(7))))
            }
        } else if Bytes.matches(identification, 0, "OpusHead"), identification.count >= 19 {
            let channels = Int(identification[9])
            preSkip = Int((try? Bytes.u16le(identification, 10)) ?? 0)
            let inputRate = Int((try? Bytes.u32le(identification, 12)) ?? 0)
            sampleRate = 48_000
            tags.format = AudioFormatInfo(codec: "Opus", sampleRate: inputRate > 0 ? inputRate : 48_000, channels: channels, isLossless: false)
            if Bytes.matches(commentPacket, 0, "OpusTags") {
                tags.fillMissing(from: VorbisComment.parse(Array(commentPacket.dropFirst(8))))
            }
        } else if Bytes.matches(identification, 0, "\u{7F}FLAC"), identification.count >= 13 + 38 {
            // Ogg FLAC: mapping header, then "fLaC" and the STREAMINFO block.
            let streamInfo = Array(identification[(13 + 4)...])
            FLAC.applyStreamInfo(streamInfo, to: &tags)
            sampleRate = tags.format?.sampleRate ?? 0
            tags.duration = nil
            if commentPacket.count > 4, commentPacket[0] & 0x7F == 4 {
                tags.fillMissing(from: VorbisComment.parse(Array(commentPacket.dropFirst(4))))
            }
        } else {
            return AudioTags()
        }

        if sampleRate > 0, let granule = try lastGranulePosition(source, serial: serial) {
            let samples = max(0, granule - Int64(preSkip))
            tags.duration = Double(samples) / Double(sampleRate)
            if let duration = tags.duration, duration > 0, tags.format?.bitRate == nil {
                tags.format?.bitRate = Int(Double(source.size) * 8 / duration)
            }
        }
        return tags
    }
}
